#!/bin/bash
#
# Bump a blueprint's version in its blueprint.hcl.
#
# One code path for humans and bots. The version gate
# (scripts/check-blueprint-bump.sh) applies to dependabot and renovate
# pull requests too, so those need a scriptable way to satisfy it:
# renovate calls this from postUpgradeTasks once it is self-hosted
# again. The /blueprint-bump-version skill keeps its batch and
# interactive role and can call this underneath.
#
# Only the quoted value on the `version` line changes; the surrounding
# alignment is preserved so the diff is one line.
#
# Usage:
#   scripts/bump-blueprint.sh <category>/<name> <major|minor|patch>
#
# Examples:
#   scripts/bump-blueprint.sh go/cli patch
#   scripts/bump-blueprint.sh bun/std minor
#
# Exit status is 0 on success, 1 on a bad argument or unparseable
# version.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Overridable so the bats suite can bump blueprints in a throwaway
# registry; defaults to the checkout this script lives in.
REGISTRY_DIR="${REGISTRY_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

die() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  sed -n '3,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

blueprint_file() {
  printf '%s/%s/blueprint.hcl\n' "$REGISTRY_DIR" "$1"
}

current_version() {
  local file="$1" line

  line="$(grep -m1 -E '^version[[:space:]]*=' "$file" || true)"

  if [[ -z "$line" ]]; then
    die "no version line in ${file}"
  fi

  # version     = "0.3.0"  ->  0.3.0
  printf '%s\n' "$line" | sed -E 's/.*"([^"]*)".*/\1/'
}

bump_semver() {
  local current="$1" level="$2"
  local major minor patch

  if [[ ! "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "cannot parse version '${current}' (expected X.Y.Z)"
  fi

  IFS='.' read -r major minor patch <<<"$current"

  case "$level" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      die "unknown level '${level}' (expected major, minor, or patch)"
      ;;
  esac

  printf '%d.%d.%d\n' "$major" "$minor" "$patch"
}

# Replace only the quoted value on the first `version` line. Written to
# a temp file and moved into place so an interrupted run cannot leave a
# half-written blueprint.hcl behind. awk rather than sed -i, which
# differs between BSD and GNU.
write_version() {
  local file="$1" new="$2" tmp

  tmp="$(mktemp)"

  awk -v version="$new" '
    !replaced && /^version[[:space:]]*=/ {
      sub(/"[^"]*"/, "\"" version "\"")
      replaced = 1
    }
    { print }
  ' "$file" >"$tmp"

  mv "$tmp" "$file"
}

main() {
  local blueprint level file current next

  if [[ $# -ne 2 ]]; then
    usage >&2
    exit 1
  fi

  blueprint="$1"
  level="$2"
  file="$(blueprint_file "$blueprint")"

  if [[ ! -f "$file" ]]; then
    die "no such blueprint: ${blueprint} (looked for ${file})"
  fi

  current="$(current_version "$file")"
  next="$(bump_semver "$current" "$level")"

  write_version "$file" "$next"

  echo "${blueprint}: ${current} -> ${next}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
