#!/bin/bash
#
# Scaffold every blueprint in the registry and report pass/fail.
#
# The registry has no build or test step — this is the verification
# gate (IMPL-0003 OQ-3a). It catches the failure modes the forge v0.8
# migration exposed: blueprint.hcl load errors, render errors from
# templates referencing variables a blueprint never declares, and
# (since the Phase 7 object migration) provider attributes that don't
# reach the templates or the condition blocks.
#
# Three passes:
#   1. default    — every blueprint on its built-in GitHub default
#   2. object     — every multi-provider blueprint with the git_provider
#                   object supplied in full, asserting the forgejo tree
#                   ships and the github tree does not
#   3. negative   — malformed provider values must be rejected before
#                   any file is written
#
# Usage:
#   scripts/scaffold-smoke.sh                  # all passes, all blueprints
#   scripts/scaffold-smoke.sh go/cli bun/std   # only these
#   KEEP=1 scripts/scaffold-smoke.sh           # keep output for inspection
#
# Exit status is the number of failed checks (0 = all green).

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REGISTRY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REGISTRY_DIR

readonly KEEP="${KEEP:-}"

# Result counters. Plain globals rather than namerefs: /bin/bash on
# macOS is 3.2, which has no `local -n`.
PASSED=0
FAILED=0

# The forgejo variant of the git_provider object. Objects replace
# wholesale — forge has no `optional()` for exact object types — so
# every attribute must be present. Kept in sync with
# docs/examples/forgejo.forge-vars.hcl.
readonly FORGEJO_OBJECT='git_provider={name="forgejo",org="homelab",host="git.fartlab.dev",renovate_config_prefix="git.fartlab.dev"}'

# Same shape, but with a name the blueprint's validation block rejects.
readonly BAD_PROVIDER_OBJECT='git_provider={name="gitlab",org="o",host="h",renovate_config_prefix="r"}'

WORK_DIR=""
cleanup() {
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    if [[ -n "$KEEP" ]]; then
      echo "output kept in ${WORK_DIR}" >&2
    else
      rm -rf "$WORK_DIR"
    fi
  fi
}
trap cleanup EXIT

err() {
  echo "$*" >&2
}

# Variables every blueprint might declare. Supplying a superset is
# safe: forge warns about and ignores unknown --set keys, and any
# variable a blueprint doesn't declare simply goes unused.
smoke_vars() {
  cat <<'EOF'
project_name=smoketest
project_owner=smokeowner
project_description=Smoke test project
project_component_type=service
project_component_system=platform
project_component_lifecycle=production
project_component_owner=platform-team
EOF
}

# Build the common --set argument array into the caller's `set_args`.
common_set_args() {
  local line
  set_args=()

  while IFS= read -r line; do
    [[ -n "$line" ]] && set_args+=(--set "$line")
  done < <(smoke_vars)
}

# List blueprint identifiers ("<category>/<name>") by finding every
# blueprint.hcl under the registry root.
list_blueprints() {
  find "$REGISTRY_DIR" -mindepth 3 -maxdepth 3 -name blueprint.hcl \
    -not -path '*/_defaults/*' -print0 |
    while IFS= read -r -d '' path; do
      dir="$(dirname "$path")"
      echo "${dir#"${REGISTRY_DIR}"/}"
    done | sort
}

# A blueprint is multi-provider when it excludes its .forgejo/ tree on
# the github path — i.e. it ships both trees and picks between them.
# The GitHub-pinned blueprints carry no .forgejo/ tree at all.
is_multi_provider() {
  grep -q 'git_provider.name != "forgejo"' \
    "${REGISTRY_DIR}/$1/blueprint.hcl" 2>/dev/null
}

# Scaffold one blueprint into `out`, with any extra --set args appended.
# Returns non-zero and prints forge's diagnostic on failure.
scaffold_one() {
  local blueprint="$1" out="$2"
  shift 2
  local -a set_args=()

  common_set_args

  forge create "$blueprint" \
    --registry-dir "$REGISTRY_DIR" \
    --output-dir "$out" \
    "${set_args[@]}" "$@" 2>&1
}

# Same, but without the common --set arguments. `--var-file` and
# `--set` are mutually exclusive on a single invocation, so var-file
# checks have to supply the whole surface through files.
scaffold_raw() {
  local blueprint="$1" out="$2"
  shift 2

  forge create "$blueprint" \
    --registry-dir "$REGISTRY_DIR" \
    --output-dir "$out" \
    "$@" 2>&1
}

# Pass 1: every blueprint on its built-in default.
run_default_pass() {
  local blueprint output file_count

  echo "── default (github) ──"

  for blueprint in "$@"; do
    if output="$(scaffold_one "$blueprint" "${WORK_DIR}/default-${blueprint//\//-}")"; then
      file_count="$(echo "$output" | grep -o 'files=[0-9]*' | head -1)"
      printf '  PASS  %-24s %s\n' "$blueprint" "${file_count:-}"
      ((PASSED += 1))
    else
      printf '  FAIL  %-24s\n' "$blueprint"
      echo "$output" | tail -3 | sed 's/^/          /' >&2
      ((FAILED += 1))
    fi
  done
}

# Pass 2: multi-provider blueprints with the object supplied in full.
# Asserts the attributes actually reached the condition blocks.
run_object_pass() {
  local blueprint out output file_count

  echo
  echo "── object supply (forgejo) ──"

  for blueprint in "$@"; do
    is_multi_provider "$blueprint" || continue

    out="${WORK_DIR}/forgejo-${blueprint//\//-}"

    if ! output="$(scaffold_one "$blueprint" "$out" --set "$FORGEJO_OBJECT")"; then
      printf '  FAIL  %-24s scaffold failed\n' "$blueprint"
      echo "$output" | tail -3 | sed 's/^/          /' >&2
      ((FAILED += 1))
      continue
    fi

    if [[ ! -d "${out}/.forgejo" ]]; then
      printf '  FAIL  %-24s .forgejo/ tree missing\n' "$blueprint"
      ((FAILED += 1))
      continue
    fi

    if [[ -d "${out}/.github" ]]; then
      printf '  FAIL  %-24s .github/ tree should be excluded\n' "$blueprint"
      ((FAILED += 1))
      continue
    fi

    file_count="$(echo "$output" | grep -o 'files=[0-9]*' | head -1)"
    printf '  PASS  %-24s %s\n' "$blueprint" "${file_count:-}"
    ((PASSED += 1))
  done
}

# Assert that a scaffold attempt fails and its diagnostic matches.
# `mode` is "set" (common --set args are supplied) or "varfile" (they
# are not, because --var-file cannot be combined with --set).
expect_failure() {
  local mode="$1" label="$2" pattern="$3" blueprint="$4"
  shift 4
  local output scaffold=scaffold_one

  [[ "$mode" == "varfile" ]] && scaffold=scaffold_raw

  if output="$("$scaffold" "$blueprint" "${WORK_DIR}/neg-$$-${RANDOM}" "$@")"; then
    printf '  FAIL  %-40s expected rejection, got success\n' "$label"
    ((FAILED += 1))

    return
  fi

  if ! grep -qF "$pattern" <<<"$output"; then
    printf '  FAIL  %-40s wrong diagnostic\n' "$label"
    echo "$output" | tail -2 | sed 's/^/          /' >&2
    ((FAILED += 1))

    return
  fi

  printf '  PASS  %-40s\n' "$label"
  ((PASSED += 1))
}

# Pass 3: malformed provider values must be rejected up front.
run_negative_pass() {
  local probe="go/cli"
  local partial="${WORK_DIR}/partial.forge-vars.hcl"
  local bad_file="${WORK_DIR}/bad-provider.forge-vars.hcl"

  echo
  echo "── negative ──"

  printf 'git_provider = {\n  name = "forgejo"\n}\n' >"$partial"
  printf 'git_provider = {\n  name                   = "gitlab"\n  org                    = "o"\n  host                   = "h"\n  renovate_config_prefix = "r"\n}\n' >"$bad_file"

  expect_failure set "bad git_provider.name via --set" \
    "git_provider.name must be one of: forgejo, github." \
    "$probe" --set "$BAD_PROVIDER_OBJECT"

  expect_failure varfile "bad git_provider.name via --var-file" \
    "git_provider.name must be one of: forgejo, github." \
    "$probe" --var-file "${REGISTRY_DIR}/docs/examples/go-cli.forge-vars.hcl" \
    --var-file "$bad_file"

  expect_failure varfile "partial object via --var-file" \
    'are required' \
    "$probe" --var-file "${REGISTRY_DIR}/docs/examples/go-cli.forge-vars.hcl" \
    --var-file "$partial"

  expect_failure set "bad license value" \
    "license must be one of" \
    "$probe" --set "license=WTFPL"
}

main() {
  command -v forge >/dev/null 2>&1 || {
    err "forge not found on PATH"
    exit 127
  }

  local -a blueprints=()
  local line
  if [[ $# -gt 0 ]]; then
    blueprints=("$@")
  else
    while IFS= read -r line; do
      blueprints+=("$line")
    done < <(list_blueprints)
  fi

  WORK_DIR="$(mktemp -d)"

  run_default_pass "${blueprints[@]}"
  run_object_pass "${blueprints[@]}"
  run_negative_pass

  echo
  echo "${PASSED} passed, ${FAILED} failed (of $((PASSED + FAILED)))"

  [[ $FAILED -eq 0 ]] || exit "$FAILED"
}

main "$@"
