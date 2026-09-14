#!/usr/bin/env bats
#
# Tests for the blueprint version gate.
#
# blueprints_requiring_bump is pure — it takes the changed paths and the
# blueprint list as arguments — so the inheritance fan-out is tested
# directly. The end-to-end cases build a throwaway registry and run the
# real script against it via REGISTRY_DIR.
#
# Run with: mise exec -- bats scripts/test/

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  GATE="${REPO_ROOT}/scripts/check-blueprint-bump.sh"
  # shellcheck source=/dev/null
  source "$GATE"

  NOOP_LABEL="dont-release"
  PR_LABELS=""

  # The registry shape the pure tests classify against.
  BLUEPRINTS="$(
    printf '%s\n' bun/std go/cli go/std homelab/go rust/std
  )"
}

paths() {
  printf '%s\n' "$@"
}

# ─── inheritance fan-out (pure) ──────────────────────────────────────

@test "a blueprint-owned file obligates just that blueprint" {
  run blueprints_requiring_bump "$(paths go/cli/justfile.tmpl)" \
    "$BLUEPRINTS"
  [ "$output" = "go/cli" ]
}

@test "a nested blueprint-owned file obligates that blueprint" {
  run blueprints_requiring_bump \
    "$(paths 'go/cli/.github/workflows/ci.yml')" "$BLUEPRINTS"
  [ "$output" = "go/cli" ]
}

@test "blueprint.hcl itself counts as a blueprint change" {
  run blueprints_requiring_bump "$(paths go/cli/blueprint.hcl)" \
    "$BLUEPRINTS"
  [ "$output" = "go/cli" ]
}

@test "a category default obligates every blueprint in that category" {
  run blueprints_requiring_bump "$(paths go/_defaults/Makefile.tmpl)" \
    "$BLUEPRINTS"
  [ "$output" = "go/cli
go/std" ]
}

@test "a registry default obligates every blueprint" {
  run blueprints_requiring_bump "$(paths _defaults/.gitignore)" \
    "$BLUEPRINTS"
  [ "$output" = "bun/std
go/cli
go/std
homelab/go
rust/std" ]
}

@test "documentation obligates nothing" {
  run blueprints_requiring_bump \
    "$(paths docs/impl/0004-thing.md README.md CHANGELOG.md)" \
    "$BLUEPRINTS"
  [ "$output" = "" ]
}

@test "workflows and scripts obligate nothing" {
  run blueprints_requiring_bump \
    "$(paths '.github/workflows/ci.yml' scripts/labels.sh registry.hcl)" \
    "$BLUEPRINTS"
  [ "$output" = "" ]
}

@test "a category-level file outside _defaults obligates nothing" {
  run blueprints_requiring_bump "$(paths go/README.md)" "$BLUEPRINTS"
  [ "$output" = "" ]
}

@test "several files touching one blueprint report it once" {
  run blueprints_requiring_bump \
    "$(paths go/cli/justfile.tmpl go/cli/blueprint.hcl go/cli/README.md)" \
    "$BLUEPRINTS"
  [ "$output" = "go/cli" ]
}

@test "overlapping obligations are merged and sorted" {
  run blueprints_requiring_bump \
    "$(paths go/_defaults/Makefile.tmpl go/cli/justfile.tmpl bun/std/x)" \
    "$BLUEPRINTS"
  [ "$output" = "bun/std
go/cli
go/std" ]
}

@test "a deleted blueprint warns instead of obligating a bump" {
  run blueprints_requiring_bump "$(paths go/gone/justfile.tmpl)" \
    "$BLUEPRINTS"
  [ "$output" = "::warning::go/gone has no blueprint.hcl on this branch; skipping" ]
}

@test "an unknown top-level directory warns about nothing" {
  run blueprints_requiring_bump "$(paths docs/examples/go-cli.hcl)" \
    "$BLUEPRINTS"
  [ "$output" = "" ]
}

# ─── label handling ──────────────────────────────────────────────────

@test "normalize_labels reads the JSON array Actions produces" {
  run normalize_labels '["documentation","dont-release","docs"]'
  [ "$output" = "documentation
dont-release
docs" ]
}

@test "normalize_labels reads a plain comma-separated list" {
  run normalize_labels "patch, ci"
  [ "$output" = "patch
ci" ]
}

@test "normalize_labels on empty input produces nothing" {
  run normalize_labels ""
  [ "$output" = "" ]
}

@test "has_noop_label finds the opt-out label in a JSON array" {
  PR_LABELS='["docs","dont-release"]'
  run has_noop_label
  [ "$status" -eq 0 ]
}

@test "has_noop_label is false when only semver labels are present" {
  PR_LABELS='["patch","ci"]'
  run has_noop_label
  [ "$status" -ne 0 ]
}

@test "has_noop_label is false with no labels at all" {
  PR_LABELS=""
  run has_noop_label
  [ "$status" -ne 0 ]
}

# ─── end to end against a throwaway registry ─────────────────────────

write_blueprint() {
  mkdir -p "${REG}/$1"
  printf 'name        = "%s"\nversion     = "%s"\n' \
    "$(echo "$1" | tr / -)" "$2" >"${REG}/$1/blueprint.hcl"
}

new_registry() {
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_SYSTEM=/dev/null

  REG="${BATS_TEST_TMPDIR}/reg"
  rm -rf "$REG"
  mkdir -p "$REG"
  cd "$REG" || return 1

  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "test"

  write_blueprint go/cli 0.1.0
  write_blueprint go/std 0.1.0
  write_blueprint bun/std 0.1.0

  mkdir -p "${REG}/_defaults" "${REG}/go/_defaults" "${REG}/docs"
  echo "shared" >"${REG}/_defaults/.gitignore"
  echo "go shared" >"${REG}/go/_defaults/Makefile.tmpl"
  echo "docs" >"${REG}/docs/readme.md"

  git add -A
  git commit -q -m "initial"
  git checkout -q -b feature
}

commit_all() {
  git add -A
  git commit -q -m "change"
}

run_gate() {
  run env REGISTRY_DIR="$REG" GITHUB_BASE_REF=main PR_LABELS="${1:-}" \
    bash "$GATE"
}

@test "a docs-only PR passes" {
  new_registry
  echo "more docs" >>"${REG}/docs/readme.md"
  commit_all
  run_gate '["dont-release"]'
  [ "$status" -eq 0 ]
  [[ "$output" == *"No blueprint changes"* ]]
}

@test "a blueprint change without a bump fails and names the blueprint" {
  new_registry
  echo "x" >"${REG}/go/cli/justfile.tmpl"
  commit_all
  run_gate '["patch"]'
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::go/cli changed without a version bump"* ]]
}

@test "a blueprint change with a bump passes" {
  new_registry
  echo "x" >"${REG}/go/cli/justfile.tmpl"
  write_blueprint go/cli 0.1.1
  commit_all
  run_gate '["patch"]'
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok  go/cli"* ]]
}

@test "bumping the wrong blueprint still fails" {
  new_registry
  echo "x" >"${REG}/go/cli/justfile.tmpl"
  write_blueprint go/std 0.1.1
  commit_all
  run_gate '["patch"]'
  [ "$status" -ne 0 ]
  [[ "$output" == *"go/cli changed without a version bump"* ]]
}

@test "a category default requires every blueprint in it to bump" {
  new_registry
  echo "changed" >"${REG}/go/_defaults/Makefile.tmpl"
  write_blueprint go/cli 0.1.1
  commit_all
  run_gate '["patch"]'
  [ "$status" -ne 0 ]
  [[ "$output" == *"go/std changed without a version bump"* ]]
  [[ "$output" != *"::error::go/cli changed"* ]]
}

@test "a category default passes when the whole category bumps" {
  new_registry
  echo "changed" >"${REG}/go/_defaults/Makefile.tmpl"
  write_blueprint go/cli 0.1.1
  write_blueprint go/std 0.1.1
  commit_all
  run_gate '["patch"]'
  [ "$status" -eq 0 ]
}

@test "a registry default requires every blueprint to bump" {
  new_registry
  echo "changed" >>"${REG}/_defaults/.gitignore"
  write_blueprint go/cli 0.1.1
  write_blueprint go/std 0.1.1
  commit_all
  run_gate '["patch"]'
  [ "$status" -ne 0 ]
  [[ "$output" == *"bun/std changed without a version bump"* ]]
}

@test "a registry default passes when all 3 blueprints bump" {
  new_registry
  echo "changed" >>"${REG}/_defaults/.gitignore"
  write_blueprint go/cli 0.1.1
  write_blueprint go/std 0.1.1
  write_blueprint bun/std 0.1.1
  commit_all
  run_gate '["minor"]'
  [ "$status" -eq 0 ]
}

@test "blueprint changes are rejected on a dont-release PR" {
  new_registry
  echo "x" >"${REG}/go/cli/justfile.tmpl"
  write_blueprint go/cli 0.1.1
  commit_all
  run_gate '["dont-release"]'
  [ "$status" -ne 0 ]
  [[ "$output" == *"labelled dont-release"* ]]
}

@test "a brand-new blueprint passes without special-casing" {
  new_registry
  write_blueprint go/brand-new 0.1.0
  commit_all
  run_gate '["minor"]'
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok  go/brand-new"* ]]
}

@test "deleting a blueprint warns and does not fail" {
  new_registry
  rm -rf "${REG:?}/go/std"
  commit_all
  run_gate '["major"]'
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::go/std has no blueprint.hcl"* ]]
}

@test "every failing blueprint is reported, not just the first" {
  new_registry
  echo "changed" >>"${REG}/_defaults/.gitignore"
  commit_all
  run_gate '["patch"]'
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::bun/std changed"* ]]
  [[ "$output" == *"::error::go/cli changed"* ]]
  [[ "$output" == *"::error::go/std changed"* ]]
  [[ "$output" == *"3 blueprint(s) changed without a version bump"* ]]
}
