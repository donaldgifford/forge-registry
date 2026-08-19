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
# that prompt for `git_provider` and derive project_org / git_host /
# renovate_config_prefix from it. go/std, go/ext, go/kubebuilder and
# the rust blueprints are GitHub-pinned instead (no git_provider key).

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

# Constrained by `contains(["forgejo", "github"], ...)`. Defaults to
# github; switching to forgejo swaps the .github/ tree for .forgejo/
# and re-derives the three variables below.
git_provider = "github"

# Constrained by `contains(["MIT", "Apache-2.0", "BSD-3-Clause",
# "none"], ...)`.
license = "Apache-2.0"

go_version = "1.26.4"

# Derived from git_provider when omitted — set them only to override:
#   github  -> donaldgifford / github.com     / github
#   forgejo -> homelab       / git.fartlab.dev / git.fartlab.dev
#
# project_org            = "donaldgifford"
# git_host               = "github.com"
# renovate_config_prefix = "github"
