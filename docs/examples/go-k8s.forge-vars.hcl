# go/k8s — full example vars file (GHCR defaults).
#
# Usage:
#   forge create go/k8s --registry-dir . \
#     --output-dir payments-api \
#     --var-file docs/examples/go-k8s.forge-vars.hcl
#
# Vars files are attribute-only HCL documents: literal values only (no
# functions, references, or blocks) and the `.hcl` extension is
# required. Keys not declared by the blueprint are warned about and
# ignored. `--var-file` is mutually exclusive with `--set`.

# ─── Required ────────────────────────────────────────────────────────

# Lowercase kebab-case (letters, digits, hyphens; starts with a letter).
project_name  = "payments-api"
project_owner = "donaldgifford"

project_description = "Payments API service"

# Backstage catalog-info entity fields.
project_component_type      = "service"
project_component_system    = "payments"
project_component_lifecycle = "experimental"
project_component_owner     = "platform"

# ─── Optional (blueprint defaults shown) ─────────────────────────────

# One of: MIT, Apache-2.0, BSD-3-Clause, none.
license = "Apache-2.0"

# Go toolchain version (go.mod, mise.toml, Dockerfile).
go_version = "1.26"

# Where CI publishes the image + chart: ghcr or ecr. Selects which
# self-contained release train lands as .github/workflows/release.yml.
container_registry = "ghcr"

# Ship ServiceMonitor + PrometheusRule chart templates. Bools are bare
# literals, not quoted strings (forge coerces "true" too, but don't).
enable_monitoring = true

# Ship helm-docs README.md.gotmpl + the docs generation recipe.
enable_helm_docs = true

# Org/user owning the repo. When omitted, the blueprint defaults this
# to project_owner — a vars file cannot express that itself (no
# references allowed), so either omit the key or set it literally.
project_org = "donaldgifford"

git_host               = "github.com"
renovate_config_prefix = "github"
