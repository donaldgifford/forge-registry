---
name: registry-validate
description: >
  Validate every blueprint in the forge registry for load-time correctness,
  schema compliance, and index freshness. Use when asked to validate the
  registry, check blueprints, or verify registry.hcl is in sync.
---

# Registry Validate

Validate all blueprints for structural correctness and the index for freshness.

There is no `forge registry validate` subcommand. Two existing commands do the
real work, and they should be run before any hand-rolled checking, because they
exercise the same loader `forge create` uses.

## 1. Load every blueprint

`forge info <path>` parses a `blueprint.hcl` through forge's loader. A malformed
type, an unknown block, a bad `validation` condition, or legacy v0.7 syntax all
surface as a load error here.

```bash
for f in $(git ls-files -- '*/*/blueprint.hcl'); do
  if forge info "$f" >/dev/null 2>&1; then
    echo "ok   $f"
  else
    echo "FAIL $f"
    forge info "$f" 2>&1 | sed 's/^/       /'
  fi
done
```

Note `forge info` takes the path to the file, not a `<category>/<name>`
reference. Passing `go/k8s` fails with "unrecognized config format".

## 2. Check the index

```bash
forge registry update --check --registry-dir .
```

Exits 0 when every entry in `registry.hcl` matches the blueprints on disk, and
non-zero listing the stale ones. Expect this to be clean on `main`.

Do **not** "fix" a failure by running `forge registry update`. The release job
owns `registry.hcl` and regenerates it after every merge. A stale result on a
branch usually means the branch is behind `main`, not that something is broken.
A stale result on `main` right after a release is a real bug — that is the drift
class
[INV-0002](../../../docs/investigation/0002-ci-enforcement-of-blueprint-version-bumps-and-registry-sync.md)
was opened for.

## 3. Required fields

Every `blueprint.hcl` carries four top-level attributes: `name`, `description`,
`version`, and `tags`. There is no `apiVersion` — that was the pre-HCL schema.

```bash
for f in $(git ls-files -- '*/*/blueprint.hcl'); do
  for field in name description version tags; do
    grep -qE "^${field}[[:space:]]*=" "$f" ||
      echo "MISSING ${field}: $f"
  done
done
```

`version` must be valid semver, since consumers pin on it:

```bash
git ls-files -- '*/*/blueprint.hcl' | while read -r f; do
  v="$(grep -m1 -E '^version[[:space:]]*=' "$f" |
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  [[ -n "$v" ]] || echo "BAD VERSION: $f"
done
```

## 4. Variable syntax

Types are **barewords**: `string`, `bool`, `number`, `list(T)`, `map(T)`,
`object({…})`. Quoted type tags and the legacy `type = "choice"` / `choices` /
`validate = "<regex>"` forms were removed in forge v0.7 and are load errors from
v0.8 on. Values are constrained with `validation` blocks instead.

Flag any legacy form that reappears:

```bash
git ls-files -- '*/*/blueprint.hcl' |
  xargs grep -n 'type *= *"\|choices *=\|^ *validate *=' || echo "clean"
```

Two namespaces, easy to confuse:

- `condition { when = … }` references variables **bare** —
  `when = container_registry == "ecr"`
- `validation { condition = … }` uses the **`var.`** namespace —
  `condition = contains(["MIT"], var.license)`

## 5. Template variable consistency

Templates are HCL2, not Go templates. References are `${variable_name}`, and
directives are `%{ if … ~}`. Extract them by dropping the escaped forms first,
then matching:

```bash
sed 's/\$\${[^}]*}//g' <file>.tmpl |
  grep -ohE '\$\{[a-zA-Z_][a-zA-Z0-9_.]*' |
  sed 's/^\${//' | cut -d. -f1 | sort -u
```

Then compare against declared variables, walking the inheritance chain:

1. the blueprint's own `blueprint.hcl`
2. `<category>/_defaults/`
3. the registry root `_defaults/`

Three things produce false positives. The `sed` above handles the first two; the
third needs judgement:

- **`$${name}` is not a forge variable.** It is a deliberate escape that emits a
  literal `${name}` for a downstream consumer — goreleaser, Docker buildx ARGs,
  shell parameter expansion, GitHub Actions expressions. Skip the `sed` and
  `go/k8s/Dockerfile.tmpl` reports `VERSION`, `COMMIT`, and `DATE` as undeclared
  variables, none of which are forge's.
- **`git_provider` is an object.** Templates traverse it as
  `${git_provider.org}`, so `cut -d. -f1` recovers the variable name.
- **Files without `.tmpl` are never parsed.** A `${…}` inside one is literal
  text. Do not flag it.

## 6. Rename mappings

`rename` blocks map a template path to its output location. Only `go/k8s` has
one today, keyed on a variable rather than on a directory name. No blueprint
currently ships a `${project_name}/` directory, so a missing rename block is not
by itself a finding — verify a template directory actually needs one.

## 7. Lint

```bash
yamllint .
markdownlint-cli2
prettier --check '**/*.md'
```

YAML files need a `---` document start and two-space indentation. Markdown prose
wraps at 80 characters.

## Output Format

```text
Registry Validation Report
==========================

Load (forge info):        19 ok, 0 failed
Index (update --check):   clean
Required fields:          19 ok
Legacy variable syntax:   none found

[PASS] go/k8s: loads, semver 0.3.0, rename block present
[WARN] go/ext: references ${foo} in README.md.tmpl, not declared
...

Summary: X passed, Y warnings, Z failures
```

## References

- [CONTRIBUTING.md](../../../CONTRIBUTING.md) — why `registry.hcl` is not
  hand-maintained
- [blueprint-schema.md](../forge-registry/references/blueprint-schema.md) —
  field requirements and types
- [conventions.md](../forge-registry/references/conventions.md) — formatting and
  template syntax
