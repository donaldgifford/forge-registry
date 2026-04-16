---
id: DESIGN-0001
title: "Claude Code Skills for Forge Registry Management"
status: Draft
author: Donald Gifford
created: 2026-04-10
---
<!-- markdownlint-disable-file MD025 MD041 -->

# DESIGN 0001: Claude Code Skills for Forge Registry Management

**Status:** Draft
**Author:** Donald Gifford
**Date:** 2026-04-10

<!--toc:start-->
- [Overview](#overview)
- [Goals and Non-Goals](#goals-and-non-goals)
  - [Goals](#goals)
  - [Non-Goals](#non-goals)
- [Background](#background)
- [Detailed Design](#detailed-design)
- [API / Interface Changes](#api--interface-changes)
- [Data Model](#data-model)
- [Testing Strategy](#testing-strategy)
- [Migration / Rollout Plan](#migration--rollout-plan)
- [Open Questions](#open-questions)
- [References](#references)
<!--toc:end-->

## Overview

A Claude Code skill plugin (`forge-registry`) that provides purpose-built
skills for managing this blueprint registry. Today, working with the registry
requires manually creating directories, writing `blueprint.yaml` files from
scratch, copying `_defaults/` patterns, and hand-editing template files. These
skills encode the registry's conventions so Claude can scaffold, validate,
update, and version-bump blueprints correctly every time.

## Goals and Non-Goals

### Goals

- Scaffold new blueprint categories and blueprints with correct directory
  structure, `blueprint.yaml`, and inherited `_defaults/`
- Add new template files (`.tmpl`) to existing blueprints with proper Go
  template syntax
- Update and validate `blueprint.yaml` fields (variables, hooks, sync, rename)
- Bump blueprint versions following semver
- List and summarize existing blueprints and their variables
- Lint blueprint YAML against the registry's yamllint/yamlfmt config
- Keep scaffolded `_defaults/` settings.json consistent with the plugin
  ecosystem (enabled plugins for each category)

### Non-Goals

- Replacing the `forge` CLI itself — these skills operate on the registry, not
  on project scaffolding output
- Auto-publishing or deploying the registry
- Managing the `forge` CLI codebase
- Generating Go or Rust application code inside templates (beyond the template
  boilerplate that already exists)

## Background

The forge-registry follows a three-tier inheritance model:

```
_defaults/           → registry-wide defaults (gitignore, linters, etc.)
<category>/_defaults/ → category-level defaults (Makefile, CI, tooling)
<category>/<name>/   → blueprint-specific files + blueprint.yaml
```

Each blueprint is defined by a `blueprint.yaml` with:

- `apiVersion`, `name`, `description`, `version`, `tags`
- `variables[]` — name, type, required, validate regex, choices, default
- `hooks` — post_create commands
- `sync` — managed_files, ignore lists
- `rename` — directory mapping (e.g., `{{project_name}}/` → `.`)

Template files use `.tmpl` extension with Go template syntax
(`{{ .variable_name }}`). Category `_defaults/` also ship Claude settings
(`.claude/settings.json`) with enabled plugins appropriate for that language.

Existing skills in the `donaldgifford-claude-skills` collection (go-development,
makefiles, mise, shell-scripting, docz, docker, etc.) already handle
language-specific concerns. The forge-registry skills focus purely on registry
structure and blueprint authoring.

## Detailed Design

### Plugin Structure

```
forge-registry/
├── plugin.yaml              # Plugin manifest
├── skills/
│   ├── scaffold/            # Create new categories and blueprints
│   │   └── skill.md
│   ├── add-template/        # Add .tmpl files to a blueprint
│   │   └── skill.md
│   ├── update-blueprint/    # Edit blueprint.yaml fields
│   │   └── skill.md
│   ├── bump-version/        # Semver version bumps
│   │   └── skill.md
│   ├── list/                # List blueprints and their metadata
│   │   └── skill.md
│   └── validate/            # Lint and validate blueprint structure
│       └── skill.md
├── agents/
│   └── registry-reviewer/   # Review agent for blueprint PRs
│       └── agent.md
└── references/
    ├── blueprint-schema.md  # blueprint.yaml schema reference
    └── conventions.md       # Registry conventions and patterns
```

### Skill Descriptions

#### `scaffold` — Create new category or blueprint

**Trigger:** "create a new blueprint", "add a go blueprint", "scaffold
rust/embedded", "new category python"

**Behavior:**

1. Determine if creating a new category or a blueprint within an existing
   category
2. For new category: create `<category>/_defaults/` with standard files
   (`.gitignore`, `.claude/settings.json`) and prompt for category-level
   tooling defaults
3. For new blueprint: create `<category>/<name>/blueprint.yaml` from a
   canonical template, prompt for variables, and create
   `{{project_name}}/README.md.tmpl`
4. Ensure `blueprint.yaml` starts with `---` (yamllint document-start rule)
5. Set initial version to `0.1.0`

**Reference files used:** `blueprint-schema.md`, `conventions.md`

#### `add-template` — Add template files to a blueprint

**Trigger:** "add a Makefile template to go/std", "create a CI workflow
template"

**Behavior:**

1. Identify target blueprint from args
2. Determine if file belongs in `_defaults/` (shared) or the specific blueprint
   directory
3. Create `.tmpl` file with Go template placeholders matching the blueprint's
   declared variables
4. Validate that all referenced `{{ .var }}` placeholders correspond to
   variables in `blueprint.yaml`

#### `update-blueprint` — Modify blueprint.yaml

**Trigger:** "add a variable to go/ext", "update the description of rust/std",
"add a post_create hook"

**Behavior:**

1. Read the target `blueprint.yaml`
2. Apply the requested changes (add/remove variables, update fields, modify
   hooks/sync/rename)
3. Validate the resulting YAML against the schema
4. Format with yamlfmt conventions (2-space indent, document start marker)

#### `bump-version` — Version management

**Trigger:** "bump go/ext version", "bump all blueprints minor"

**Behavior:**

1. Read current `version` from `blueprint.yaml`
2. Apply semver bump (major/minor/patch, default: patch)
3. Optionally bump all blueprints in a category or the entire registry
4. Report the version changes as a summary table

#### `list` — Enumerate blueprints

**Trigger:** "list blueprints", "what blueprints exist", "show go blueprints"

**Behavior:**

1. Walk the registry directory structure
2. Parse each `blueprint.yaml`
3. Output a summary table: category, name, version, variable count, tags

#### `validate` — Lint and validate

**Trigger:** "validate the registry", "lint blueprints", "check blueprint
structure"

**Behavior:**

1. Verify directory structure follows the three-tier convention
2. Validate each `blueprint.yaml` against the expected schema
3. Check that `.tmpl` files only reference declared variables
4. Run yamllint on all YAML files
5. Report errors and warnings

### Reference Files

#### `blueprint-schema.md`

Documents the full `blueprint.yaml` schema:

- Required fields: `apiVersion` (v1), `name`, `description`, `version`
- Optional fields: `tags`, `variables`, `hooks`, `sync`, `rename`
- Variable types: `string`, `choice`
- Variable fields: `name`, `description`, `type`, `required`, `validate`,
  `choices`, `default`
- Hook types: `post_create`
- Sync fields: `managed_files`, `ignore`
- Rename field: maps directory patterns to output paths

#### `conventions.md`

Documents registry patterns:

- Directory naming: lowercase, hyphenated
- YAML: `---` document start, 2-space indent, yamlfmt formatting
- Template syntax: `{{ .variable_name }}` (with spaces inside braces)
- Directory templates: `{{project_name}}/` (no spaces, no dot prefix)
- Category `_defaults/` should include `.claude/settings.json` with relevant
  plugins enabled
- `_defaults/` files at category level override registry-level `_defaults/`

### Registry Reviewer Agent

An agent (`registry-reviewer`) that reviews blueprint PRs:

- Validates `blueprint.yaml` schema
- Checks template variable consistency
- Verifies `_defaults/` inheritance is correct
- Confirms YAML formatting compliance
- Flags missing `rename:` mappings for blueprints with `{{project_name}}/`
  directories

## API / Interface Changes

New slash commands available when the plugin is enabled:

| Command | Description |
|---------|-------------|
| `/scaffold` | Create a new category or blueprint |
| `/add-template` | Add a template file to a blueprint |
| `/update-blueprint` | Modify blueprint.yaml fields |
| `/bump-version` | Semver bump blueprint versions |
| `/list` | List blueprints and metadata |
| `/validate` | Lint and validate registry structure |

The plugin also adds the `registry-reviewer` agent type for use with the
Agent tool.

## Data Model

No new data models. The skills operate on the existing file-based structure:

- `blueprint.yaml` — the source of truth for each blueprint
- `.tmpl` files — Go template files
- `_defaults/` directories — inherited configuration files

## Testing Strategy

- **Manual validation:** Run each skill against the existing go/ and rust/
  categories and verify output matches conventions
- **Scaffold round-trip:** Create a new blueprint with `/scaffold`, add
  templates with `/add-template`, then run `/validate` to confirm consistency
- **Version bump verification:** Bump versions and confirm `blueprint.yaml`
  reflects correct semver
- **Regression:** Run `/validate` across the entire registry after any skill
  operation to catch structural drift

## Migration / Rollout Plan

1. **Phase 1:** Create the plugin with `scaffold`, `list`, and `validate`
   skills and the reference files. These are read-heavy and low-risk.
2. **Phase 2:** Add `update-blueprint`, `add-template`, and `bump-version`
   skills that modify files.
3. **Phase 3:** Add the `registry-reviewer` agent.
4. **Phase 4:** Add the plugin to `_defaults/.claude/settings.json` so
   scaffolded projects inherit it, and to this repo's
   `.claude/settings.json`.

## Open Questions

- Should `scaffold` call `forge init` under the hood, or replicate the
  structure directly? Using `forge init` ensures parity but adds a runtime
  dependency.
- Should `bump-version` support coordinated bumps across dependent blueprints
  (e.g., all go/ blueprints share `_defaults/` so a defaults change might
  warrant bumping all)?
- Should there be a `sync-defaults` skill that propagates changes from
  `_defaults/` to existing blueprints, or is that `forge sync`'s job?
- Where should the plugin source live — in this registry repo itself, or in
  a separate plugin repo? Keeping it here ties the skills to the registry
  conventions directly.

## References

- [forge CLI](https://github.com/donaldgifford/forge) — the CLI that consumes
  this registry
- [skill-creator plugin](https://github.com/donaldgifford/claude-skills) —
  guide for building Claude Code plugins
- Existing blueprints: `go/std`, `go/ext`, `rust/std`, `rust/esp32`
