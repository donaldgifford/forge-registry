#!/bin/bash
#
# Implementation of the pr-semver-tag composite action. See action.yml
# for the input and output contract.
#
# The two modes share one computation: find the PR whose squash-merge
# produced GITHUB_SHA, map its labels to a bump level, read the latest
# reachable tag, and increment. `compute` stops there. `tag` also
# creates an annotated tag on INPUT_TARGET (HEAD by default), pushes it,
# and comments the version on the PR.
#
# Every step is guarded or idempotent so a failed release job can be
# re-run: the computation is stateless, and tagging refuses to move an
# existing tag.
#
# Usage (outside CI, for debugging):
#   GITHUB_REPOSITORY=owner/repo GITHUB_SHA=<sha> INPUT_MODE=compute \
#     .github/actions/pr-semver-tag/entrypoint.sh
#
# Exit status is 0 on success, including every "skip" path. A non-zero
# status means the release genuinely could not proceed.

set -Eeuo pipefail

# Resolved from the action inputs. Deliberately not readonly: the bats
# suite sources this file and overrides them per case.
MODE="${INPUT_MODE:-}"
MAJOR_LABEL="${INPUT_MAJOR_LABEL:-major}"
MINOR_LABEL="${INPUT_MINOR_LABEL:-minor}"
PATCH_LABEL="${INPUT_PATCH_LABEL:-patch}"
NOOP_LABELS="${INPUT_NOOP_LABELS:-dont-release}"
TAG_PREFIX="${INPUT_TAG_PREFIX:-v}"
TARGET="${INPUT_TARGET:-HEAD}"

# gh reads GH_TOKEN; the action passes the token as INPUT_GITHUB_TOKEN.
if [[ -n "${INPUT_GITHUB_TOKEN:-}" ]]; then
  export GH_TOKEN="${INPUT_GITHUB_TOKEN}"
fi

log() {
  echo "$*" >&2
}

# GitHub renders ::warning:: and ::error:: in the job log and the run
# summary; plain echo would bury a skip reason in the step output.
warn() {
  echo "::warning::$*" >&2
}

die() {
  echo "::error::$*" >&2
  exit 1
}

# Write one action output. A no-op outside CI, which keeps the script
# runnable by hand for debugging.
set_output() {
  local name="$1" value="$2"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$name" "$value" >>"$GITHUB_OUTPUT"
  fi
}

# Split a comma-, space-, or newline-separated list into one item per
# line, dropping empties. Used for the noop-label list and for label
# arrays coming out of jq.
split_list() {
  printf '%s\n' "$1" | tr ',' '\n' | tr -s '[:blank:]' '\n' |
    grep -v '^$' || true
}

is_noop_label() {
  local candidate="$1" noop

  while IFS= read -r noop; do
    if [[ "$candidate" == "$noop" ]]; then
      return 0
    fi
  done < <(split_list "$NOOP_LABELS")

  return 1
}

# Map a newline-separated label list to a bump level.
#
# An opt-out label wins over everything, so a PR carrying both
# `dont-release` and `patch` releases nothing rather than silently
# picking one. Among semver labels the precedence is major > minor >
# patch. pr-labels.yml already enforces exactly one label, so the
# precedence is defense in depth rather than a documented interface.
bump_level_from_labels() {
  local labels="$1"
  local label
  local found="none"

  while IFS= read -r label; do
    if is_noop_label "$label"; then
      printf 'none\n'
      return 0
    fi

    case "$label" in
      "$MAJOR_LABEL")
        found="major"
        ;;
      "$MINOR_LABEL")
        if [[ "$found" != "major" ]]; then
          found="minor"
        fi
        ;;
      "$PATCH_LABEL")
        if [[ "$found" == "none" ]]; then
          found="patch"
        fi
        ;;
      *) ;;
    esac
  done < <(split_list "$labels")

  printf '%s\n' "$found"
}

# Latest prefixed tag reachable from HEAD.
#
# `--merged HEAD` means a tag pushed on an unmerged branch cannot be
# read as the current version. That is stricter than querying the tags
# API, and it avoids the unpaginated-listing bug that made
# pr-semver-bump miscompute past ~100 tags (INV-0002 Observation 11).
current_version() {
  local latest

  latest="$(git tag --merged HEAD --list "${TAG_PREFIX}[0-9]*" |
    sort -V | tail -1)"

  if [[ -z "$latest" ]]; then
    printf '%s0.0.0\n' "$TAG_PREFIX"
    return 0
  fi

  printf '%s\n' "$latest"
}

next_version() {
  local current="$1" level="$2"
  local bare major minor patch

  bare="${current#"$TAG_PREFIX"}"

  if [[ ! "$bare" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "cannot parse version '${current}' (expected ${TAG_PREFIX}X.Y.Z)"
  fi

  IFS='.' read -r major minor patch <<<"$bare"

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
      die "unknown bump level: ${level}"
      ;;
  esac

  printf '%s%d.%d.%d\n' "$TAG_PREFIX" "$major" "$minor" "$patch"
}

# The PR whose squash-merge produced GITHUB_SHA, as compact JSON.
#
# GITHUB_SHA stays pinned to that merge commit for the whole run even
# after the job pushes new commits, so this lookup still resolves in
# `tag` mode (INV-0002 Verified Behavior). Emits nothing when the commit
# has no associated PR, which is the direct-push and workflow_dispatch
# case.
find_pr() {
  gh api "repos/${GITHUB_REPOSITORY}/commits/${GITHUB_SHA}/pulls" \
    --jq '.[0] | select(. != null)
          | {number, title, labels: [.labels[].name]}'
}

create_tag() {
  local version="$1" pr_number="$2" pr_title="$3"

  if git rev-parse -q --verify "refs/tags/${version}" >/dev/null; then
    die "tag ${version} already exists; refusing to move it"
  fi

  git config user.name "github-actions[bot]"
  git config user.email \
    "41898282+github-actions[bot]@users.noreply.github.com"

  git tag -a "$version" "$TARGET" \
    -m "${version}: PR #${pr_number} - ${pr_title}"
  git push origin "refs/tags/${version}"

  log "tagged ${TARGET} as ${version}"

  local url="${GITHUB_SERVER_URL:-https://github.com}"
  url="${url}/${GITHUB_REPOSITORY}/tree/${version}"

  # A failed comment must not fail an otherwise complete release: the
  # tag is already pushed and re-running would hit the guard above.
  if ! gh pr comment "$pr_number" \
    --body "Released as [\`${version}\`](${url})."; then
    warn "tag ${version} pushed, but commenting on PR #${pr_number} failed"
  fi
}

emit_skip() {
  local pr_number="${1:-}"

  set_output skip true
  set_output bump-level none
  set_output current-version "$(current_version)"
  set_output next-version ""
  set_output pr-number "$pr_number"
}

require_env() {
  local name

  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      die "${name} is not set"
    fi
  done
}

main() {
  local pr_json pr_number pr_title labels level current next

  case "$MODE" in
    compute | tag) ;;
    "") die "mode is required (compute | tag)" ;;
    *) die "unknown mode '${MODE}' (expected compute | tag)" ;;
  esac

  require_env GITHUB_REPOSITORY GITHUB_SHA

  pr_json="$(find_pr)"

  if [[ -z "$pr_json" ]]; then
    warn "no pull request found for ${GITHUB_SHA}; nothing to release"
    emit_skip
    return 0
  fi

  pr_number="$(jq -r '.number' <<<"$pr_json")"
  pr_title="$(jq -r '.title' <<<"$pr_json")"
  labels="$(jq -r '.labels[]' <<<"$pr_json")"

  level="$(bump_level_from_labels "$labels")"

  if [[ "$level" == "none" ]]; then
    log "PR #${pr_number} carries no releasable label; skipping"
    emit_skip "$pr_number"
    return 0
  fi

  current="$(current_version)"
  next="$(next_version "$current" "$level")"

  set_output skip false
  set_output bump-level "$level"
  set_output current-version "$current"
  set_output next-version "$next"
  set_output pr-number "$pr_number"

  log "PR #${pr_number}: ${level} bump ${current} -> ${next}"

  if [[ "$MODE" == "tag" ]]; then
    create_tag "$next" "$pr_number" "$pr_title"
  fi
}

# Sourcing the file (as the bats suite does) defines the functions
# without running anything.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
