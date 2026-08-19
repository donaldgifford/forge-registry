#!/bin/bash
#
# Scaffold every blueprint in the registry and report pass/fail.
#
# The registry has no build or test step — this is the verification
# gate (IMPL-0003 OQ-3a). It catches the two failure modes the forge
# v0.8 migration exposed: blueprint.hcl load errors, and render errors
# from templates referencing variables a blueprint never declares.
#
# Usage:
#   scripts/scaffold-smoke.sh              # scaffold all blueprints
#   scripts/scaffold-smoke.sh go/cli bun/std   # only these
#   KEEP=1 scripts/scaffold-smoke.sh       # keep output for inspection
#
# Exit status is the number of failed blueprints (0 = all green).

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REGISTRY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REGISTRY_DIR

readonly KEEP="${KEEP:-}"

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

# Scaffold one blueprint into the work dir. Returns non-zero and
# prints forge's diagnostic on failure.
scaffold_one() {
  local blueprint="$1"
  local out="${WORK_DIR}/${blueprint//\//-}"
  local -a set_args=()
  local line

  while IFS= read -r line; do
    [[ -n "$line" ]] && set_args+=(--set "$line")
  done < <(smoke_vars)

  forge create "$blueprint" \
    --registry-dir "$REGISTRY_DIR" \
    --output-dir "$out" \
    "${set_args[@]}" 2>&1
}

main() {
  command -v forge >/dev/null 2>&1 || {
    err "forge not found on PATH"
    exit 127
  }

  local -a blueprints=()
  if [[ $# -gt 0 ]]; then
    blueprints=("$@")
  else
    while IFS= read -r line; do
      blueprints+=("$line")
    done < <(list_blueprints)
  fi

  WORK_DIR="$(mktemp -d)"

  local passed=0 failed=0
  local blueprint output file_count

  for blueprint in "${blueprints[@]}"; do
    if output="$(scaffold_one "$blueprint")"; then
      file_count="$(echo "$output" | grep -o 'files=[0-9]*' | head -1)"
      printf '  PASS  %-24s %s\n' "$blueprint" "${file_count:-}"
      ((passed += 1))
    else
      printf '  FAIL  %-24s\n' "$blueprint"
      # Forge diagnostics are one long line; show it indented.
      echo "$output" | tail -3 | sed 's/^/          /' >&2
      ((failed += 1))
    fi
  done

  echo
  echo "${passed} passed, ${failed} failed (of $((passed + failed)))"

  [[ $failed -eq 0 ]] || exit "$failed"
}

main "$@"
