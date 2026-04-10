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

Each blueprint has a `blueprint.yaml` defining its name, variables, hooks, sync
rules, and rename mappings. Templates use Go template syntax
(`{{ .variable_name }}`).

## Key Conventions

- **Blueprint variables** are defined in `blueprint.yaml` with name, type,
  validation regex, and optional choices/defaults
- **Template files** use `.tmpl` extension and Go template syntax
- **`_defaults/` directories** provide inherited files — category-level defaults
  override registry-level defaults
- **`rename:` in blueprint.yaml** maps template directory names (e.g.,
  `{{project_name}}/`) to their output location (`.`)
- YAML files require document start marker (`---`) per yamllint config
- YAML indentation: 2 spaces
- Markdown prose wrapped at 80 characters (prettier)

## Linting

This repo has no build step or tests. Quality is enforced via config linters:

- `yamllint` / `yamlfmt` for YAML files
- `markdownlint-cli2` for Markdown
- `prettier` for Markdown prose wrapping

## Adding a New Blueprint

```bash
forge init <category>/<name> --registry .
```

Then define variables in `blueprint.yaml`, add template files, and leverage
`_defaults/` for shared config.
