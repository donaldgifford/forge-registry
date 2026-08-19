# Examples

Example `*.forge-vars.hcl` files for scaffolding blueprints non-interactively
with `forge create --var-file` (forge v0.8+, DESIGN-0005/IMPL-0008 in the forge
repo).

## Files

| File                        | Purpose                                                |
| --------------------------- | ------------------------------------------------------ |
| `go-k8s.forge-vars.hcl`     | Full go/k8s example — every variable, GHCR train       |
| `go-k8s-ecr.forge-vars.hcl` | Overlay flipping the release train to ECR              |
| `go-cli.forge-vars.hcl`     | Full go/cli example — the multi-provider surface       |
| `forgejo.forge-vars.hcl`    | Overlay retargeting any blueprint at `git.fartlab.dev` |

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
  context, so `project_description = project_name` or `upper("x")` are load
  errors. Cross-variable defaults (e.g. the GitHub-pinned blueprints defaulting
  `git_provider.org` to `project_owner`) live in the blueprint — omit the key to
  get them.
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
variables, and vars files take all three as plain HCL literals. `--set` accepts
an object only as a quoted HCL-literal string and rejects `list`/`map` outright
("use --var-file to supply list and map values"); interactive prompting unfolds
an object one field at a time. So vars files are the only ergonomic channel for
structured values.

Every blueprint declares exactly one object variable today: `git_provider`,
carrying the provider identity and the three values derived from it — see
[forge-registry#14](https://github.com/donaldgifford/forge-registry/issues/14)
and IMPL-0003 Phase 7.

```hcl
git_provider = {
  name                   = "github"
  org                    = "donaldgifford"
  host                   = "github.com"
  renovate_config_prefix = "github"
}
```

**Objects replace wholesale.** All four attributes are required whenever the key
is present — forge has no `optional()` for exact object types, so a partial
object fails before anything is written:

```console
Error: loading vars file: vars file partial.hcl:1,16: variable "git_provider"
expects object, got object: attributes "host", "org", and
"renovate_config_prefix" are required
```

Omit the key entirely to take the blueprint default. That is also why there is
no `--set git_provider=forgejo` shorthand any more: use the
`forgejo.forge-vars.hcl` overlay, or pass the whole object as a `--set` HCL
literal.

`--set` accepts an object as a quoted HCL literal but rejects `list`/`map`
variables outright ("use --var-file to supply list and map values"), and
interactive prompting unfolds an object one field at a time. Vars files take all
three as plain HCL literals.

## Value constraints

Every blueprint is on the forge v0.8 variable syntax (IMPL-0003), so enum-like
variables are enforced by `validation` blocks rather than a `choices` list.
Supplying an out-of-range value fails before any file is written, with the
blueprint's own error message and the offending declaration's position:

```console
$ forge create go/cli --registry-dir . --output-dir demo \
    --var-file docs/examples/go-cli.forge-vars.hcl --var-file gitlab.hcl
Error: validating variables: git_provider.name must be one of: forgejo, github.
  (variable "git_provider", go/cli/blueprint.hcl:58,3-13)
```

Object attributes validate the same way, and the check fires identically whether
the value arrived through `--set` or a vars file. The same applies to `license`
and, for go/k8s, `container_registry`. Variables constrained this way are listed
with their allowed values in each blueprint's `blueprint.hcl`.
