# forge-registry

Blueprint registry for the [forge](https://github.com/donaldgifford/forge) CLI:
project templates (blueprints) that `forge` uses to scaffold new repositories.

## Structure

```text
├── registry.hcl         # Registry index (generated on main by the release job)
├── _defaults/           # Registry-wide default files
├── go/                  # Go blueprints
│   ├── _defaults/       # Shared Go defaults (justfile, CI workflows, mise, ...)
│   └── std/ ext/ cli/ docker/ k8s/ kubebuilder/
├── rust/                # Rust blueprints (std, esp32)
├── bun/                 # Bun blueprints (std)
├── homelab/             # Homelab blueprints (go, k8s, charts, tf-*, ...)
└── std/                 # Generic blueprints (docs, new)
```

Each blueprint has a `blueprint.hcl` defining its name, variables, hooks, sync
rules, and rename mappings. Template files use HCL2 syntax with the `.tmpl`
extension — files without it are copied verbatim. `_defaults/` directories
provide inherited files; category-level defaults override registry-level ones.

## Using a blueprint

```bash
forge create go/k8s --registry-dir . --output-dir my-svc \
  --var-file docs/examples/go-k8s.forge-vars.hcl
```

`--set key=value` covers scalar variables, but `list`/`map` values can only be
supplied via `--var-file` — see [docs/examples/](docs/examples/) for annotated
vars files and the file format rules.

## Adding a blueprint

```bash
forge registry blueprint <category>/<name> --registry-dir .
```

Then define variables in `blueprint.hcl`, add `.tmpl` template files, and lean
on `_defaults/` for shared config. Do not run `forge registry update` — the
release job regenerates `registry.hcl` on `main`, where a squash-merge has not
yet orphaned the pins.

> `go/k8s` is written in forge v0.8 variable syntax (bareword types +
> `validation` blocks); the remaining blueprints stay on the legacy syntax until
> the registry-wide migration
> ([#14](https://github.com/donaldgifford/forge-registry/issues/14)).

## Changing a blueprint

Blueprints are pinned by `version`, so an edit without a bump changes what
consumers get under a version they already resolved. CI enforces the bump:

```bash
scripts/bump-blueprint.sh go/k8s patch   # rewrite the version in place
scripts/check-blueprint-bump.sh          # what the gate will ask for
```

Every pull request also carries exactly one release label — `major`, `minor`,
`patch`, or `dont-release` — which the release job reads to decide what to tag.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the full lifecycle.

## Linting

Blueprints have no build step; quality is enforced with `yamllint` / `yamlfmt`,
`markdownlint-cli2`, and `prettier` (Markdown prose wrapped at 80 characters).
The release automation under `scripts/` and `.github/actions/` is covered by
`shellcheck`, `shfmt`, and bats.
