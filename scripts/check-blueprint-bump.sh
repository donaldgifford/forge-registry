#!/bin/bash
#
# Fail a pull request that changes a blueprint without bumping that
# blueprint's version.
#
# Consumers pin blueprints by version through registry.hcl, so a
# behavior change that ships under the version already pinned is
# invisible to them (IMPL-0004 Phase 2). This gate makes the bump
# mandatory at review time rather than something to notice later.
#
# Inheritance means a changed file can obligate more than one
# blueprint. Forge layers registry `_defaults/`, then
# `<category>/_defaults/`, then the blueprint directory, so:
#
#   _defaults/**            → every blueprint must bump
#   <category>/_defaults/** → every blueprint in that category
#   <category>/<name>/**    → that blueprint
#
# Anything else (docs, workflows, scripts, registry.hcl) is ignored.
#
# There is no exemption for bot pull requests. A dependency bump inside
# a blueprint directory is a change consumers should receive, so
# dependabot and renovate are held to the same rule; scripts/bump-
# blueprint.sh is the shared way to satisfy it.
#
# Usage:
#   scripts/check-blueprint-bump.sh
#
# Environment:
#   GITHUB_BASE_REF  branch the PR targets (default: main)
#   PR_LABELS        the PR's labels, as the JSON array GitHub Actions
#                    produces or a plain comma-separated list
#
# Exit status is 0 when every obligated blueprint bumped, 1 otherwise.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Overridable so the bats suite can point the whole script at a
# throwaway registry; defaults to the checkout this script lives in.
REGISTRY_DIR="${REGISTRY_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# Not readonly: the bats suite sources this file and overrides them.
BASE_REF="${GITHUB_BASE_REF:-main}"
PR_LABELS="${PR_LABELS:-}"
NOOP_LABEL="${NOOP_LABEL:-dont-release}"

err() {
  echo "$*" >&2
}

# GitHub renders these in the job log and the run summary, and anchors
# them to the PR's Files Changed tab.
annotate_error() {
  echo "::error::$*" >&2
}

annotate_warning() {
  echo "::warning::$*" >&2
}

die() {
  annotate_error "$*"
  exit 1
}

list_contains() {
  local haystack="$1" needle="$2" item

  while IFS= read -r item; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done <<<"$haystack"

  return 1
}

# Every blueprint on the current branch, as `<category>/<name>`.
#
# Reading the branch rather than the base means a blueprint added by
# this very PR is discovered. Its wholesale-new blueprint.hcl contains
# a `+version` line by construction, so a new blueprint passes without
# being special-cased.
all_blueprints() {
  git ls-files -- '*/*/blueprint.hcl' | sed 's|/blueprint.hcl$||'
}

# The distinct top-level directories that hold blueprints, so paths
# under docs/ or scripts/ are never mistaken for blueprint paths.
categories_of() {
  printf '%s\n' "$1" | cut -d/ -f1 | sort -u
}

resolve_base() {
  if git rev-parse -q --verify "origin/${BASE_REF}" >/dev/null; then
    printf 'origin/%s\n' "$BASE_REF"
    return 0
  fi

  if git rev-parse -q --verify "$BASE_REF" >/dev/null; then
    printf '%s\n' "$BASE_REF"
    return 0
  fi

  die "cannot resolve base ref '${BASE_REF}'"
}

changed_files() {
  git diff --name-only "$1...HEAD"
}

# Map changed paths to the blueprints that must bump.
#
# Pure: both lists are arguments, so the bats suite exercises the
# inheritance fan-out without building a git fixture.
#
#   $1  newline-separated changed paths
#   $2  newline-separated blueprint dirs
blueprints_requiring_bump() {
  local changed="$1" blueprints="$2"
  local categories path bp category rest tail_path candidate
  local required=""

  categories="$(categories_of "$blueprints")"

  while IFS= read -r path; do
    if [[ -z "$path" ]]; then
      continue
    fi

    case "$path" in
      _defaults/*)
        required="${required}${blueprints}"$'\n'
        continue
        ;;
      */_defaults/*)
        category="${path%%/*}"
        while IFS= read -r bp; do
          if [[ "${bp%%/*}" == "$category" ]]; then
            required="${required}${bp}"$'\n'
          fi
        done <<<"$blueprints"
        continue
        ;;
    esac

    # Blueprint-owned paths have at least three segments:
    # <category>/<name>/<file>. Fewer means a category-level or
    # top-level file that no blueprint owns.
    category="${path%%/*}"
    rest="${path#*/}"
    if [[ "$rest" == "$path" ]]; then
      continue
    fi

    tail_path="${rest#*/}"
    if [[ "$tail_path" == "$rest" ]]; then
      continue
    fi

    candidate="${category}/${rest%%/*}"

    if list_contains "$blueprints" "$candidate"; then
      required="${required}${candidate}"$'\n'
    elif list_contains "$categories" "$category"; then
      # A path under a real category whose blueprint.hcl is gone: the
      # blueprint is being deleted. Registry entry removal is manual
      # today, so warn and move on rather than demanding a bump on a
      # file that no longer exists.
      annotate_warning \
        "${candidate} has no blueprint.hcl on this branch; skipping"
    fi
  done <<<"$changed"

  printf '%s' "$required" | grep -v '^$' | sort -u || true
}

# Normalize PR_LABELS to one label per line. GitHub Actions passes a
# JSON array via toJSON(); a human running this by hand is likelier to
# pass a comma-separated list.
normalize_labels() {
  local raw="$1"

  if [[ -z "$raw" ]]; then
    return 0
  fi

  if [[ "$raw" == \[* ]]; then
    printf '%s' "$raw" | jq -r '.[]'
    return 0
  fi

  printf '%s\n' "$raw" | tr ',' '\n' | tr -s '[:blank:]' '\n' |
    grep -v '^$' || true
}

has_noop_label() {
  local label

  while IFS= read -r label; do
    if [[ "$label" == "$NOOP_LABEL" ]]; then
      return 0
    fi
  done < <(normalize_labels "$PR_LABELS")

  return 1
}

version_bumped() {
  local base="$1" blueprint="$2"

  git diff "${base}...HEAD" -- "${blueprint}/blueprint.hcl" |
    grep -qE '^\+version[[:space:]]*='
}

main() {
  local base changed blueprints required blueprint failures=0

  cd "$REGISTRY_DIR"

  base="$(resolve_base)"
  changed="$(changed_files "$base")"
  blueprints="$(all_blueprints)"
  required="$(blueprints_requiring_bump "$changed" "$blueprints")"

  if [[ -z "$required" ]]; then
    echo "No blueprint changes; nothing to check."
    return 0
  fi

  echo "Blueprints requiring a version bump:"
  while IFS= read -r blueprint; do
    echo "  ${blueprint}"
  done <<<"$required"

  # A blueprint change is by definition releasable, so it cannot ride
  # along on a PR that opts out of releasing.
  if has_noop_label; then
    annotate_error \
      "this PR changes blueprints but is labelled ${NOOP_LABEL};" \
      "blueprint changes need major, minor, or patch"
    return 1
  fi

  while IFS= read -r blueprint; do
    if version_bumped "$base" "$blueprint"; then
      echo "  ok  ${blueprint}"
    else
      annotate_error \
        "${blueprint} changed without a version bump in" \
        "${blueprint}/blueprint.hcl —" \
        "run scripts/bump-blueprint.sh ${blueprint} <major|minor|patch>"
      failures=$((failures + 1))
    fi
  done <<<"$required"

  if ((failures > 0)); then
    err "${failures} blueprint(s) changed without a version bump"
    return 1
  fi

  echo "All changed blueprints bumped their version."
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
