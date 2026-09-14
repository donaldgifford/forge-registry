#!/usr/bin/env bats
#
# Unit tests for the pr-semver-tag entrypoint.
#
# entrypoint.sh guards its `main` call on BASH_SOURCE, so sourcing it
# here defines the functions without running the action. Everything
# covered below is either pure or needs only a throwaway git repo — the
# gh-dependent paths (find_pr, create_tag) are exercised end to end in
# Phase 4 instead of being mocked.
#
# Run with: mise exec -- bats .github/actions/pr-semver-tag/test/

setup() {
  ACTION_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # shellcheck source=/dev/null
  source "${ACTION_DIR}/entrypoint.sh"

  # Restore the documented defaults: sourcing picks up whatever INPUT_*
  # happens to be in the caller's environment.
  MAJOR_LABEL="major"
  MINOR_LABEL="minor"
  PATCH_LABEL="patch"
  NOOP_LABELS="dont-release"
  TAG_PREFIX="v"
  TARGET="HEAD"
}

# A newline-separated label list, the shape jq hands to
# bump_level_from_labels.
labels() {
  printf '%s\n' "$@"
}

# A throwaway repo, isolated from the developer's and the runner's git
# configuration. Without the /dev/null overrides a global `tag.gpgSign`
# turns `git tag` into an annotated signed tag and the fixture dies with
# "no tag message?".
new_repo() {
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_SYSTEM=/dev/null

  cd "$BATS_TEST_TMPDIR" || return 1
  rm -rf repo
  mkdir repo
  cd repo || return 1
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "test"
  git commit -q --allow-empty -m "initial"
}

# ─── split_list ──────────────────────────────────────────────────────

@test "split_list splits on commas" {
  run split_list "a,b,c"
  [ "$status" -eq 0 ]
  [ "$output" = "a
b
c" ]
}

@test "split_list splits on spaces and drops empties" {
  run split_list "a, b ,,c"
  [ "$status" -eq 0 ]
  [ "$output" = "a
b
c" ]
}

@test "split_list on an empty string produces nothing" {
  run split_list ""
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# ─── bump_level_from_labels ──────────────────────────────────────────

@test "major label selects a major bump" {
  run bump_level_from_labels "$(labels major)"
  [ "$output" = "major" ]
}

@test "minor label selects a minor bump" {
  run bump_level_from_labels "$(labels minor)"
  [ "$output" = "minor" ]
}

@test "patch label selects a patch bump" {
  run bump_level_from_labels "$(labels patch)"
  [ "$output" = "patch" ]
}

@test "an unrelated label alone releases nothing" {
  run bump_level_from_labels "$(labels documentation)"
  [ "$output" = "none" ]
}

@test "no labels at all releases nothing" {
  run bump_level_from_labels ""
  [ "$output" = "none" ]
}

@test "semver labels are picked out of unrelated ones" {
  run bump_level_from_labels "$(labels documentation patch chore)"
  [ "$output" = "patch" ]
}

@test "major wins over minor and patch regardless of order" {
  run bump_level_from_labels "$(labels patch minor major)"
  [ "$output" = "major" ]
}

@test "minor wins over patch regardless of order" {
  run bump_level_from_labels "$(labels patch minor)"
  [ "$output" = "minor" ]
}

@test "an opt-out label beats a semver label on the same PR" {
  run bump_level_from_labels "$(labels patch dont-release)"
  [ "$output" = "none" ]
}

@test "an opt-out label beats a major label" {
  run bump_level_from_labels "$(labels major dont-release)"
  [ "$output" = "none" ]
}

@test "any label in a multi-entry noop list opts out" {
  NOOP_LABELS="dont-release,skip-release"
  run bump_level_from_labels "$(labels skip-release patch)"
  [ "$output" = "none" ]
}

@test "custom semver label names are honored" {
  MAJOR_LABEL="breaking"
  run bump_level_from_labels "$(labels breaking)"
  [ "$output" = "major" ]
}

@test "the default label names stop applying when overridden" {
  MAJOR_LABEL="breaking"
  run bump_level_from_labels "$(labels major)"
  [ "$output" = "none" ]
}

# ─── next_version ────────────────────────────────────────────────────

@test "patch increments the patch component" {
  run next_version "v0.1.4" "patch"
  [ "$output" = "v0.1.5" ]
}

@test "minor increments minor and zeroes patch" {
  run next_version "v0.1.4" "minor"
  [ "$output" = "v0.2.0" ]
}

@test "major increments major and zeroes minor and patch" {
  run next_version "v0.1.4" "major"
  [ "$output" = "v1.0.0" ]
}

@test "a fresh repo's 0.0.0 base increments" {
  run next_version "v0.0.0" "patch"
  [ "$output" = "v0.0.1" ]
}

@test "components do not carry when they reach 9" {
  run next_version "v0.9.9" "minor"
  [ "$output" = "v0.10.0" ]
}

@test "multi-digit components are arithmetic, not string, increments" {
  run next_version "v1.10.99" "patch"
  [ "$output" = "v1.10.100" ]
}

@test "an empty tag prefix round-trips" {
  TAG_PREFIX=""
  run next_version "1.2.3" "minor"
  [ "$output" = "1.3.0" ]
}

@test "a custom tag prefix is preserved" {
  TAG_PREFIX="release-"
  run next_version "release-1.2.3" "patch"
  [ "$output" = "release-1.2.4" ]
}

@test "a malformed version fails loudly" {
  run next_version "v1.2" "patch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot parse version"* ]]
}

@test "a non-numeric version fails loudly" {
  run next_version "vX.Y.Z" "patch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot parse version"* ]]
}

@test "an unknown bump level fails loudly" {
  run next_version "v1.2.3" "sideways"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown bump level"* ]]
}

# ─── current_version ─────────────────────────────────────────────────

@test "a repo with no tags reports the zero base" {
  new_repo
  run current_version
  [ "$output" = "v0.0.0" ]
}

@test "the newest tag by version order wins, not by string order" {
  new_repo
  git tag v0.9.0
  git tag v0.10.0
  run current_version
  [ "$output" = "v0.10.0" ]
}

@test "tags on unmerged branches are ignored" {
  new_repo
  git tag v0.1.0
  git checkout -q -b side
  git commit -q --allow-empty -m "side"
  git tag v9.9.9
  git checkout -q main
  run current_version
  [ "$output" = "v0.1.0" ]
}

@test "tags that do not match the prefix are ignored" {
  new_repo
  git tag v0.1.0
  git tag nightly-2026-09-10
  run current_version
  [ "$output" = "v0.1.0" ]
}

@test "a custom prefix selects only its own tags" {
  new_repo
  TAG_PREFIX="release-"
  git tag v9.9.9
  git tag release-1.2.3
  run current_version
  [ "$output" = "release-1.2.3" ]
}

# ─── set_output ──────────────────────────────────────────────────────

@test "set_output appends key=value to GITHUB_OUTPUT" {
  GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/out"
  : >"$GITHUB_OUTPUT"
  set_output next-version "v1.2.3"
  set_output skip "false"
  run cat "$GITHUB_OUTPUT"
  [ "$output" = "next-version=v1.2.3
skip=false" ]
}

@test "set_output is a no-op outside CI" {
  unset GITHUB_OUTPUT
  run set_output next-version "v1.2.3"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
