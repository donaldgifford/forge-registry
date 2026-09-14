# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What This Is

A **blueprint registry** for the `forge` CLI tool. It contains project templates
(blueprints) that `forge` uses to scaffold new repositories. This is NOT
application code — it's a collection of template files, config defaults, and
blueprint definitions.

## Architecture

```text
_defaults/              # Registry-wide defaults (shared across all categories)
├── .gitignore, .markdownlint.yaml, .prettierrc.yaml, etc.
go/                     # Go blueprints
├── _defaults/          # Shared Go defaults (Makefile.tmpl, golangci.yml, CI workflows, mise.toml.tmpl)
├── std/                # Go standard blueprint (minimal)
└── ext/                # Go extended blueprint (more variables, CI, security workflow)
rust/                   # Rust blueprints
├── _defaults/          # Shared Rust defaults (Makefile, Cargo.toml, clippy/rustfmt, CI workflows)
├── std/                # Rust standard blueprint
└── esp32/              # Rust ESP32 embedded blueprint
```

Each blueprint has a `blueprint.hcl` defining its name, variables, hooks, sync
rules, and rename mappings. Templates use HCL2 (`hashicorp/hcl/v2`) syntax:
`${variable_name}` for substitution, `%{ if … ~}` for directives. The registry
index is `registry.hcl` at the repo root.

## Key Conventions

- **Blueprint variables** are defined in `blueprint.hcl` as
  `variable "name" { type = string, description = …, default = …, required = … }`
  blocks. Types are **barewords** (`string`, `bool`, `number`, `object({…})`,
  `list(T)`, `map(T)`) — quoted type tags and the legacy `type = "choice"` /
  `choices` / `validate = "<regex>"` forms were removed in forge v0.7 and are
  load errors from v0.8 on. Constrain values with `validation` blocks:

  ```hcl
  variable "license" {
    description = "License type"
    type        = string
    default     = "Apache-2.0"

    validation {
      condition     = contains(["MIT", "Apache-2.0", "none"], var.license)
      error_message = "license must be one of: MIT, Apache-2.0, none."
    }
  }
  ```

  Conditions reference variables bare (`when = git_provider.name != "github"`),
  while `validation` conditions use the `var.` namespace.

- **`git_provider` is an object**, declared identically in all 19 blueprints:
  `object({ name, org, host, renovate_config_prefix })`. Templates traverse it
  (`${git_provider.org}`), conditions test `git_provider.name`, and validations
  use `var.git_provider.name`. Objects **replace wholesale** — forge has no
  `optional()` for exact object types, so supplying the key at all means
  supplying all four attributes. Omit it to take the blueprint default; use
  `docs/examples/forgejo.forge-vars.hcl` to retarget at forgejo. An object
  `default` may reference earlier variables (`org = project_owner`), which the
  GitHub-pinned blueprints rely on.
- **Template files** use `.tmpl` extension and HCL2 syntax. Files without
  `.tmpl` are copied verbatim and never parsed by the engine.
- **`_defaults/` directories** provide inherited files — category-level defaults
  override registry-level defaults (last wins).
- **`rename` blocks in blueprint.hcl** map template directory names (e.g.,
  `${project_name}/`) to their output location (`.`). The template directory
  name itself uses `${project_name}` syntax, not `{{project_name}}`.
- **Escape `${...}` for downstream tools** — goreleaser, Docker buildx ARGs,
  shell parameter expansion, GitHub Actions expressions all use `${name}` as
  their own substitution syntax. Write `$${name}` in templates so HCL2 emits a
  literal `${name}` for the downstream consumer. Forge variables use bare
  `${name}`.
- YAML files require document start marker (`---`) per yamllint config.
- YAML indentation: 2 spaces.
- Markdown prose wrapped at 80 characters (prettier).

## Linting

Blueprints have no build step — they are template files, so quality is enforced
with config linters:

- `yamllint` / `yamlfmt` for YAML files
- `markdownlint-cli2` for Markdown
- `prettier` for Markdown prose wrapping

None of these run in CI — run them by hand, and scope them to the files you
touched, because `prettier` and `markdownlint-cli2` both report pre-existing
failures under `.claude/skills/`.

The release automation under `scripts/` and `.github/actions/` is real code and
does have tests:

```bash
shellcheck scripts/*.sh .github/actions/pr-semver-tag/entrypoint.sh
shfmt -d -i 2 -ci scripts/*.sh .github/actions/pr-semver-tag/entrypoint.sh
bats scripts/test/ .github/actions/pr-semver-tag/test/
```

## Adding a New Blueprint

```bash
forge registry blueprint <category>/<name> --registry-dir .
```

Then define variables in `blueprint.hcl`, add template files (using HCL2 syntax
with `.tmpl` extension), and leverage `_defaults/` for shared config.

**Do not run `forge registry update`.** The release job owns `registry.hcl` and
regenerates it on `main` after every merge. Pins written on a branch are stale
the moment a squash-merge rewrites the commit they were computed from, so a
`registry.hcl` diff on a PR should be dropped, not committed. The same goes for
`CHANGELOG.md` — `git-cliff` writes it once per release, inside the release
commit.

## Release Workflow

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full lifecycle. The parts that
change how you make edits:

- **Blueprint edits require a `version` bump**, enforced by the
  `Blueprint Version Gate` job. Bump with
  `scripts/bump-blueprint.sh <category>/<name> <major|minor|patch>`, and see
  what the gate wants with `scripts/check-blueprint-bump.sh`.
- **Editing a shared default fans out.** A change under the root `_defaults/`
  needs a bump on all 19 blueprints; under `<category>/_defaults/`, on that
  category's blueprints.
- **Every PR carries exactly one release label**: `major`, `minor`, `patch`, or
  `dont-release`. Docs-only changes take `dont-release`. A blueprint change plus
  `dont-release` is rejected by the gate.
- **PR titles must be conventional commits.** The repo squash-merges, so the
  title becomes the commit subject and is the only input `git-cliff` gets. A
  scope of `<category>/<name>` (categories `bun|go|homelab|rust|std`) routes the
  entry into the **Blueprint Changes** section.
- **Shell scripts are tested.** `shellcheck`, `shfmt -i 2 -ci`, and bats suites
  under `scripts/test/` and `.github/actions/pr-semver-tag/test/` all run in CI.

## Local Skills

This repo includes Claude Code skills in `.claude/skills/` for registry
management:

| Slash Command             | Description                                                        |
| ------------------------- | ------------------------------------------------------------------ |
| `/forge-registry`         | General registry knowledge and quick reference                     |
| `/registry-list`          | List all blueprints with metadata table                            |
| `/registry-validate`      | Validate registry structure and blueprint schemas                  |
| `/blueprint-scaffold`     | Create new categories or blueprints via `forge registry blueprint` |
| `/blueprint-update`       | Modify blueprint.hcl fields (variables, hooks, sync)               |
| `/blueprint-add-template` | Add .tmpl files with variable cross-referencing                    |
| `/blueprint-bump-version` | Semver version bumps (single or batch)                             |
| `/registry-review`        | Review blueprint changes against conventions                       |

> **Most of these skill docs are stale.** Only `/blueprint-bump-version` and
> `/registry-validate` have been brought up to date. The other eight still
> describe a `blueprint.yaml` file that no longer exists, Go-template
> `{{ .var }}` syntax instead of HCL2 `${var}`, and the `type: choice` /
> `choices` / `validate` variable forms that forge removed in v0.7. Treat this
> file and [CONTRIBUTING.md](CONTRIBUTING.md) as authoritative over them until
> they are rewritten.
