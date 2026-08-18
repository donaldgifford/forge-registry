# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What This Is

A **blueprint registry** for the `forge` CLI tool. It contains project templates
(blueprints) that `forge` uses to scaffold new repositories. This is NOT
application code — it's a collection of template files, config defaults, and
blueprint definitions.

## Architecture

```
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

- **Blueprint variables** are defined in `blueprint.hcl` as `variable "name"
  { type = string, description = …, default = …, required = … }` blocks.
  Types are **barewords** (`string`, `bool`, `number`, `object({…})`,
  `list(T)`, `map(T)`) — quoted type tags and the legacy `type = "choice"` /
  `choices` / `validate = "<regex>"` forms were removed in forge v0.7 and
  are load errors from v0.8 on. Constrain values with `validation` blocks:

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

  Conditions reference variables bare (`when = git_provider != "github"`),
  while `validation` conditions use the `var.` namespace.
- **Template files** use `.tmpl` extension and HCL2 syntax. Files without
  `.tmpl` are copied verbatim and never parsed by the engine.
- **`_defaults/` directories** provide inherited files — category-level defaults
  override registry-level defaults (last wins).
- **`rename` blocks in blueprint.hcl** map template directory names (e.g.,
  `${project_name}/`) to their output location (`.`). The template directory
  name itself uses `${project_name}` syntax, not `{{project_name}}`.
- **Escape `${...}` for downstream tools** — goreleaser, Docker buildx ARGs,
  shell parameter expansion, GitHub Actions expressions all use `${name}` as
  their own substitution syntax. Write `$${name}` in templates so HCL2 emits
  a literal `${name}` for the downstream consumer. Forge variables use
  bare `${name}`.
- YAML files require document start marker (`---`) per yamllint config.
- YAML indentation: 2 spaces.
- Markdown prose wrapped at 80 characters (prettier).

## Linting

This repo has no build step or tests. Quality is enforced via config linters:

- `yamllint` / `yamlfmt` for YAML files
- `markdownlint-cli2` for Markdown
- `prettier` for Markdown prose wrapping

## Adding a New Blueprint

```bash
forge registry blueprint <category>/<name> --registry-dir .
```

Then define variables in `blueprint.hcl`, add template files (using HCL2
syntax with `.tmpl` extension), and leverage `_defaults/` for shared config.
`forge registry update --registry-dir .` keeps `registry.hcl` in sync after
edits.

## Local Skills

This repo includes Claude Code skills in `.claude/skills/` for registry
management:

| Slash Command | Description |
|---------------|-------------|
| `/forge-registry` | General registry knowledge and quick reference |
| `/registry-list` | List all blueprints with metadata table |
| `/registry-validate` | Validate registry structure and blueprint schemas |
| `/blueprint-scaffold` | Create new categories or blueprints via `forge registry blueprint` |
| `/blueprint-update` | Modify blueprint.hcl fields (variables, hooks, sync) |
| `/blueprint-add-template` | Add .tmpl files with variable cross-referencing |
| `/blueprint-bump-version` | Semver version bumps (single or batch) |
| `/registry-review` | Review blueprint changes against conventions |
