#!/usr/bin/env bats
#
# Tests for the blueprint version bump helper.
#
# The semver arithmetic and the line rewriting are covered directly.
# The command-line behavior runs the real script against a throwaway
# registry via REGISTRY_DIR.
#
# Run with: mise exec -- bats scripts/test/

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  BUMP="${REPO_ROOT}/scripts/bump-blueprint.sh"
  # shellcheck source=/dev/null
  source "$BUMP"

  REG="${BATS_TEST_TMPDIR}/reg"
  rm -rf "$REG"
  mkdir -p "${REG}/go/cli"
}

# A blueprint.hcl shaped like the real ones: the version value is
# column-aligned and sits between other top-level attributes.
fixture_blueprint() {
  cat >"${REG}/go/cli/blueprint.hcl" <<EOF
name        = "go-cli"
description = "go cli blueprint"
version     = "${1}"
tags        = ["go", "cli"]

variable "project_name" {
  description = "Name of the project"
  type        = string
}
EOF
}

run_bump() {
  run env REGISTRY_DIR="$REG" bash "$BUMP" "$@"
}

# ─── bump_semver ─────────────────────────────────────────────────────

@test "patch increments the patch component" {
  run bump_semver "0.3.0" "patch"
  [ "$output" = "0.3.1" ]
}

@test "minor increments minor and zeroes patch" {
  run bump_semver "0.3.4" "minor"
  [ "$output" = "0.4.0" ]
}

@test "major increments major and zeroes minor and patch" {
  run bump_semver "0.3.4" "major"
  [ "$output" = "1.0.0" ]
}

@test "components do not carry at 9" {
  run bump_semver "0.9.9" "patch"
  [ "$output" = "0.9.10" ]
}

@test "multi-digit components increment arithmetically" {
  run bump_semver "1.10.99" "minor"
  [ "$output" = "1.11.0" ]
}

@test "a two-component version is rejected" {
  run bump_semver "0.3" "patch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot parse version"* ]]
}

@test "a v-prefixed version is rejected" {
  run bump_semver "v0.3.0" "patch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot parse version"* ]]
}

@test "an unknown level is rejected" {
  run bump_semver "0.3.0" "sideways"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown level"* ]]
}

# ─── current_version and write_version ───────────────────────────────

@test "current_version reads the aligned version value" {
  fixture_blueprint "0.3.0"
  run current_version "${REG}/go/cli/blueprint.hcl"
  [ "$output" = "0.3.0" ]
}

@test "current_version fails on a file with no version line" {
  printf 'name = "x"\n' >"${REG}/go/cli/blueprint.hcl"
  run current_version "${REG}/go/cli/blueprint.hcl"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no version line"* ]]
}

@test "write_version preserves the surrounding alignment" {
  fixture_blueprint "0.3.0"
  write_version "${REG}/go/cli/blueprint.hcl" "0.4.0"
  run grep -n 'version' "${REG}/go/cli/blueprint.hcl"
  [[ "$output" == *'version     = "0.4.0"'* ]]
}

@test "write_version leaves every other line untouched" {
  fixture_blueprint "0.3.0"
  cp "${REG}/go/cli/blueprint.hcl" "${BATS_TEST_TMPDIR}/before"
  write_version "${REG}/go/cli/blueprint.hcl" "0.4.0"
  run diff "${BATS_TEST_TMPDIR}/before" "${REG}/go/cli/blueprint.hcl"
  # One line changed: one deletion and one addition.
  [ "$(grep -c '^<' <<<"$output")" -eq 1 ]
  [ "$(grep -c '^>' <<<"$output")" -eq 1 ]
}

@test "write_version does not touch a later quoted string" {
  fixture_blueprint "0.3.0"
  write_version "${REG}/go/cli/blueprint.hcl" "0.4.0"
  run cat "${REG}/go/cli/blueprint.hcl"
  [[ "$output" == *'tags        = ["go", "cli"]'* ]]
  [[ "$output" == *'description = "Name of the project"'* ]]
}

# ─── command line ────────────────────────────────────────────────────

@test "bumping a blueprint reports the transition" {
  fixture_blueprint "0.3.0"
  run_bump go/cli patch
  [ "$status" -eq 0 ]
  [ "$output" = "go/cli: 0.3.0 -> 0.3.1" ]
}

@test "the bump is written to the file" {
  fixture_blueprint "0.3.0"
  run_bump go/cli minor
  run grep 'version' "${REG}/go/cli/blueprint.hcl"
  [[ "$output" == *'"0.4.0"'* ]]
}

@test "successive bumps compound" {
  fixture_blueprint "0.3.0"
  run_bump go/cli patch
  run_bump go/cli patch
  run current_version "${REG}/go/cli/blueprint.hcl"
  [ "$output" = "0.3.2" ]
}

@test "an unknown blueprint is rejected" {
  run_bump go/nope patch
  [ "$status" -ne 0 ]
  [[ "$output" == *"no such blueprint"* ]]
}

@test "an unknown level is rejected at the command line" {
  fixture_blueprint "0.3.0"
  run_bump go/cli sideways
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown level"* ]]
}

@test "a bad level does not modify the file" {
  fixture_blueprint "0.3.0"
  run_bump go/cli sideways
  run current_version "${REG}/go/cli/blueprint.hcl"
  [ "$output" = "0.3.0" ]
}

@test "too few arguments prints usage" {
  run_bump go/cli
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "no arguments prints usage" {
  run_bump
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}
