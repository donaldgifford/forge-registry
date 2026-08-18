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
variables — and vars files are the only full channel for supplying them: `--set`
rejects `list`/`map` variables outright ("use --var-file to supply list and map
values"), accepts objects only as a quoted HCL-literal string, and interactive
prompting is scalar-only. Vars files take all three as plain HCL literals:

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

Until that migration lands (IMPL-0003 Phases 6–8), the registry's blueprints use
`string` and `bool` variables only — see the example files for the real surface.

## Value constraints

Every blueprint is on the forge v0.8 variable syntax (IMPL-0003), so enum-like
variables are enforced by `validation` blocks rather than a `choices` list.
Supplying an out-of-range value fails before any file is written, with the
blueprint's own error message and the offending declaration's position:

```console
$ forge create go/cli --registry-dir . --output-dir demo \
    --set git_provider=gitlab ...
Error: validating variables: git_provider must be one of: forgejo, github.
  (variable "git_provider", go/cli/blueprint.hcl:44,3-13)
```

The same applies to `license` and, for go/k8s, `container_registry`. Variables
constrained this way are listed with their allowed values in each blueprint's
`blueprint.hcl`.
