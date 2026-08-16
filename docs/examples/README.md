# Examples

Example `*.forge-vars.hcl` files for scaffolding blueprints non-interactively
with `forge create --var-file` (forge v0.8+, DESIGN-0005/IMPL-0008 in the forge
repo).

## Files

| File                        | Purpose                                          |
| --------------------------- | ------------------------------------------------ |
| `go-k8s.forge-vars.hcl`     | Full go/k8s example — every variable, GHCR train |
| `go-k8s-ecr.forge-vars.hcl` | Overlay flipping the release train to ECR        |

## Usage

```sh
forge create go/k8s --registry-dir . \
  --output-dir payments-api \
  --var-file docs/examples/go-k8s.forge-vars.hcl
```

Files are repeatable and compose left-to-right — later files override earlier
ones on key collision, so overlays only carry deltas:

```sh
forge create go/k8s --registry-dir . \
  --output-dir payments-api \
  --var-file docs/examples/go-k8s.forge-vars.hcl \
  --var-file docs/examples/go-k8s-ecr.forge-vars.hcl
```

Any declared variable the files don't set falls back to its blueprint default
(or an interactive prompt if it's required and has none).

## File format

Vars files are **attribute-only HCL** with strict literal values:

- The `.hcl` extension is required.
- Top-level blocks are rejected — assignments only.
- No functions, no references, no traversals: values are evaluated in an empty
  context, so `project_org = project_owner` or `upper("x")` are load errors.
  Cross-variable defaults (e.g. go/k8s's `project_org` defaulting to
  `project_owner`) live in the blueprint — omit the key to get them.
- Keys that don't match a declared blueprint variable are warned about and
  ignored.
- `--var-file` is mutually exclusive with `--set`.

Values are coerced to the blueprint's declared types, so bare literals of the
right shape are all that's needed:

```hcl
project_name      = "payments-api" # string
enable_monitoring = false          # bool — bare, not "false"
```

## Structured types (forge v0.8 / IMPL-0009)

forge v0.8 blueprints can declare `object({...})`, `list(...)`, and `map(...)`
variables; vars files supply them as plain HCL literals:

```hcl
# Hypothetical — no registry blueprint declares these yet. Issue #14
# plans to collapse the git-provider scalar cluster into an object
# variable registry-wide, at which point a vars file would set it as:
git_provider = {
  host   = "github.com"
  org    = "donaldgifford"
  prefix = "github"
}

extra_topics = ["go", "kubernetes", "helm"]
```

Until that migration lands, the registry's blueprints use `string` and `bool`
variables only — see the go/k8s example files for the real surface.
