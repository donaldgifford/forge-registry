# go/cli — full example vars file (multi-provider cluster surface).
#
# Usage:
#   forge create go/cli --registry-dir . \
#     --output-dir release-tool \
#     --var-file docs/examples/go-cli.forge-vars.hcl
#
# Vars files are attribute-only HCL documents: literal values only (no
# functions, references, or blocks) and the `.hcl` extension is
# required. Keys not declared by the blueprint are warned about and
# ignored. `--var-file` is mutually exclusive with `--set`.
#
# go/cli is the reference for the *cluster* surface — the 13 blueprints
# that ship both a .github/ and a .forgejo/ tree and pick between them
# on `git_provider.name`. go/std, go/ext, go/kubebuilder, go/k8s and the
# rust blueprints declare the same object but are GitHub-pinned: they
# carry no .forgejo/ tree, so only the derived attributes matter there.

# ─── Required ────────────────────────────────────────────────────────

# Lowercase kebab-case (letters, digits, hyphens; starts with a letter)
# — enforced by a `validation { can(regex(...)) }` block.
project_name  = "release-tool"
project_owner = "donaldgifford"

project_description = "Release automation CLI"

# Backstage catalog-info.yaml identity — all four are required.
project_component_type      = "service"
project_component_system    = "platform"
project_component_lifecycle = "production"
project_component_owner     = "platform-team"

# ─── Optional (blueprint defaults shown) ─────────────────────────────

# Provider identity and everything derived from it (issue #14) — one
# object variable, replacing the former git_provider enum plus the
# project_org / git_host / renovate_config_prefix scalars it drove.
#
# `name` is constrained by `contains(["forgejo", "github"], ...)` and
# selects which tree ships: github keeps .github/ and drops .forgejo/,
# forgejo does the reverse.
#
# Objects replace wholesale — all four attributes are required whenever
# the key is present, because forge has no `optional()` for exact object
# types. Omit the key entirely to take the blueprint default (the values
# shown here).
#
# For the forgejo variant, compose docs/examples/forgejo.forge-vars.hcl
# on top of this file rather than editing it.
git_provider = {
  name                   = "github"
  org                    = "donaldgifford"
  host                   = "github.com"
  renovate_config_prefix = "github"
}

# Constrained by `contains(["MIT", "Apache-2.0", "BSD-3-Clause",
# "none"], ...)`.
license = "Apache-2.0"

go_version = "1.26.4"
