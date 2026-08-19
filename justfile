# forge-registry — task runner
#
# Project automation via just. Use either the Makefile or this justfile —
# both expose the same target set with equivalent behavior.

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

project_name      := "forge-registry"
project_owner     := "donaldgifford"
allowed_licenses  := "Apache-2.0,MIT,BSD-2-Clause,BSD-3-Clause,ISC,MPL-2.0"

# Version info derived from git; falls back to dev when not in a repo or tag-less.
commit_hash := `git rev-parse --short HEAD 2>/dev/null || echo unknown`
version     := `git describe --tags --always --dirty 2>/dev/null || echo dev`

# Default: list recipes
_default:
    @just --list --unsorted

# ─── Lint & format ─────────────────────────────────────────────────

# Run markdownlint-cli2
[group('lint')]
lint-md:
    @markdownlint-cli2 ./...

# Run markdownlint-cli2 with --fix
[group('lint')]
lint-md-fix:
    @markdownlint-cli2 --fix ./...

# Run yamllint
[group('lint')]
lint-yaml:
    @yamllint ./...

# Run yamllint with --fix
[group('lint')]
lint-yaml-fix:
    @yamllint --fix ./...

# Run yamlfmt
[group('lint')]
fmt-yaml:
    @yamlfmt ./...

# Lint GitHub Actions workflows
[group('lint')]
lint-actions:
    @actionlint


# Run prettier
[group('lint')]
fmt-prettier:
    @prettier

# ─── Composite gates ────────────────────────────────────────────────

# Pre-commit gate: lint + test
[group('gate')]
check: lint
    @echo "✓ Pre-commit checks passed"
