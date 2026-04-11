---
name: forge-registry
description: >
  Forge blueprint registry management. Use when working with blueprint
  definitions, template files, registry structure, or asking about how
  blueprints work. Triggers on: blueprint, registry, template, forge,
  scaffold, blueprint.yaml, _defaults.
---

# Forge Registry

Guidance for managing the forge blueprint registry — a collection of project
templates consumed by the `forge` CLI.

## Core Principles

- **Three-tier inheritance** — `_defaults/` (registry-wide) is overridden by
  `<category>/_defaults/` (category-level), which is overridden by
  `<category>/<name>/` (blueprint-specific)
- **Go template syntax** — `.tmpl` files use `{{ .variable_name }}` (spaces
  inside braces); directory names use `{{variable_name}}` (no spaces, no dot)
- **YAML conventions** — document start marker (`---`), 2-space indent,
  yamlfmt formatting
- **`forge init`** — always use the CLI to scaffold new blueprints:
  `forge init <category>/<name> --registry .`
- **Variables are the contract** — every `{{ .var }}` in a template must
  correspond to a declared variable in `blueprint.yaml`

## Reference Files

Read these when you encounter the specific topic.

| Topic | File | When to read |
|-------|------|--------------|
| **Blueprint Schema** | [references/blueprint-schema.md](references/blueprint-schema.md) | Editing blueprint.yaml, adding variables, understanding field types |
| **Conventions** | [references/conventions.md](references/conventions.md) | Creating directories, naming, inheritance rules, template syntax |

## Quick Reference

```bash
# Scaffold a new blueprint
forge init go/myblueprint --registry .

# List all blueprints
find . -name blueprint.yaml -not -path './_defaults/*'

# Validate YAML
yamllint .

# Available local skills
/registry-list              # List blueprints with metadata
/registry-validate          # Lint and validate registry structure
/blueprint-scaffold         # Create new category or blueprint
/blueprint-update           # Modify blueprint.yaml fields
/blueprint-add-template     # Add .tmpl files to a blueprint
/blueprint-bump-version     # Semver version bumps
/registry-review            # Review blueprint changes
```
