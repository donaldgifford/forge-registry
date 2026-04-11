---
id: IMPL-0001
title: "Forge Registry Skills Plugin"
status: Draft
author: Donald Gifford
created: 2026-04-10
---
<!-- markdownlint-disable-file MD025 MD041 -->

# IMPL 0001: Forge Registry Skills Plugin

**Status:** Draft
**Author:** Donald Gifford
**Date:** 2026-04-10

<!--toc:start-->
- [Objective](#objective)
- [Scope](#scope)
  - [In Scope](#in-scope)
  - [Out of Scope](#out-of-scope)
- [Implementation Phases](#implementation-phases)
  - [Phase 1: <!-- Foundation / Setup / Core -->](#phase-1----foundation--setup--core)
    - [Tasks](#tasks)
    - [Success Criteria](#success-criteria)
  - [Phase 2: <!-- Core Feature / Primary Commands -->](#phase-2----core-feature--primary-commands)
    - [Tasks](#tasks-1)
    - [Success Criteria](#success-criteria-1)
  - [Phase 3: <!-- Polish / Edge Cases / CI Readiness -->](#phase-3----polish--edge-cases--ci-readiness)
    - [Tasks](#tasks-2)
    - [Success Criteria](#success-criteria-2)
- [File Changes](#file-changes)
- [Testing Plan](#testing-plan)
- [Dependencies](#dependencies)
- [References](#references)
<!--toc:end-->

## Objective

Implement local Claude Code skills for this forge-registry repo as described
in DESIGN-0001. The skills live in `.claude/skills/` and are available
whenever Claude Code operates in this repo — no external plugin needed.

**Implements:** DESIGN-0001 — Claude Code Skills for Forge Registry Management

## Scope

### In Scope

- Local skills in `.claude/skills/` with reference files
- Six skills: `registry-list`, `registry-validate`, `blueprint-scaffold`,
  `blueprint-update`, `blueprint-add-template`, `blueprint-bump-version`
- Reference files: `blueprint-schema.md`, `conventions.md`
- `forge` CLI as the scaffolding tool (install via mise if missing)
- `rust/_defaults/.claude/settings.json` creation

### Out of Scope

- Distributable plugin infrastructure (no `.claude-plugin/plugin.json`)
- Changes to the `forge` CLI itself
- New blueprint categories (the skills enable creating them, but we don't
  create any new ones in this impl)

## Implementation Phases

Each phase builds on the previous one. A phase is complete when all its tasks
are checked off and its success criteria are met.

---

### Phase 1: Skills Directory and Reference Files

Establish the `.claude/skills/` structure and the reference documents that
all skills depend on. No user-facing skills are functional yet — this phase
creates the shared knowledge base.

#### Tasks

- [x] Create `.claude/skills/` directory structure
- [x] Create `.claude/skills/forge-registry/SKILL.md` — the main skill
      entry point with:
  - Frontmatter: `name: forge-registry`, description with trigger phrases
    for general registry questions
  - Core principles: three-tier inheritance, template syntax, YAML
    conventions
  - References table pointing to the two reference files
  - Quick reference for common operations
- [x] Create `.claude/skills/forge-registry/references/blueprint-schema.md`
      documenting the full `blueprint.yaml` schema:
  - Required fields: `apiVersion` (v1), `name`, `description`, `version`
  - Optional fields: `tags`, `variables`, `hooks`, `sync`, `rename`
  - Variable object: `name`, `description`, `type` (string|choice),
    `required`, `validate`, `choices`, `default`
  - Hooks object: `post_create` (list of shell commands)
  - Sync object: `managed_files`, `ignore` (both lists)
  - Rename object: key-value map of directory patterns to output paths
  - Include annotated examples from existing blueprints (`go/ext`,
    `rust/std`)
- [x] Create `.claude/skills/forge-registry/references/conventions.md`
      documenting:
  - Three-tier inheritance model (`_defaults/` → `<cat>/_defaults/` →
    `<cat>/<name>/`)
  - Directory naming: lowercase, hyphenated
  - YAML formatting: `---` document start, 2-space indent
  - Template syntax: `{{ .variable_name }}` (spaces inside braces) for
    file contents; `{{variable_name}}` (no spaces, no dot) for directory
    names
  - `.tmpl` extension convention
  - `_defaults/.claude/settings.json` pattern for plugin inheritance
  - How `rename:` maps `{{project_name}}/` to `.`
- [x] Ensure `forge` is listed in mise config or document it as a
      prerequisite (install via `mise install`) — forge 0.2.0 available
      via mise

#### Success Criteria

- `.claude/skills/forge-registry/SKILL.md` exists with valid YAML
  frontmatter (`name` and `description` fields)
- Both reference files exist and cover every field/pattern found in the
  existing five blueprints (`go/std`, `go/ext`, `rust/std`, `rust/esp32`,
  `std/`)
- References table in SKILL.md links both reference files with "when to
  read" guidance

---

### Phase 2: Read-Only Skills (registry-list, registry-validate)

Deliver the two skills that inspect but do not modify the registry. These are
safe to iterate on without risk of corrupting blueprint files.

#### Tasks

- [x] Create `.claude/skills/registry-list/SKILL.md` with:
  - Frontmatter: `name: registry-list`, description with trigger phrases
  - Trigger phrases: "list blueprints", "what blueprints exist", "show go
    blueprints", "registry status"
  - Instructions to walk the registry tree, find all `blueprint.yaml`
    files, parse them, and output a markdown table with columns:
    category, name, version, variable count, tags
  - Include the root-level `std/` blueprint (category shown as `(root)`)
  - Optional category filter from `$ARGUMENTS`
- [x] Create `.claude/skills/registry-validate/SKILL.md` with:
  - Frontmatter: `name: registry-validate`, description with trigger
    phrases
  - Trigger phrases: "validate the registry", "lint blueprints", "check
    blueprint structure"
  - Validation checklist:
    1. Every `blueprint.yaml` has required fields (`apiVersion`, `name`,
       `description`, `version`)
    2. Variables with `type: choice` have a non-empty `choices` list
    3. Variables with `validate` have a valid regex
    4. `.tmpl` files only reference variables declared in their
       blueprint's `blueprint.yaml` (walk `{{ .var }}` patterns)
    5. Every blueprint directory with a `{{project_name}}/` subdirectory
       has a corresponding `rename:` entry
    6. YAML files pass yamllint (run `yamllint` if available)
  - Output format: pass/fail per check, with file paths for failures
  - Reference: `forge-registry/references/blueprint-schema.md`
- [x] Test `/registry-list` against the existing registry — verified 5
      blueprints: go/std, go/ext, rust/std, rust/esp32, std
- [x] Test `/registry-validate` against the existing registry — yamllint
      reports 4 warnings (missing document-start on go/std, rust/std,
      rust/esp32, std); documented in conventions.md as known issue

#### Success Criteria

- `/registry-list` outputs a table with exactly 5 rows (go/std, go/ext,
  rust/std, rust/esp32, std) when run against the current registry
- `/registry-validate` runs all six checks and produces a clear pass/fail
  report
- Both skills reference the shared reference files from
  `forge-registry/references/`

---

### Phase 3: Scaffold Skill (blueprint-scaffold)

Implement the most complex write skill — creating new categories and
blueprints via `forge init`.

#### Tasks

- [ ] Create `.claude/skills/blueprint-scaffold/SKILL.md` with:
  - Frontmatter: `name: blueprint-scaffold`, description with trigger
    phrases
  - Trigger phrases: "create a new blueprint", "add a go blueprint",
    "scaffold rust/embedded", "new category python"
  - Decision logic: determine if the user is creating a new category or a
    new blueprint within an existing category
  - **New category workflow:**
    1. Create `<category>/` directory
    2. Create `<category>/_defaults/` with:
       - `.gitignore` (copy pattern from existing category defaults)
       - `.claude/settings.json` with baseline plugins enabled
    3. Prompt user for category-level tooling (language, build tool, etc.)
    4. Create first blueprint via `forge init` (below)
  - **New blueprint workflow:**
    1. Run `forge init <category>/<name> --registry .` to scaffold the
       blueprint using the same flow a user would
    2. If `forge` is not installed, install it via `mise install forge`
    3. Review and adjust the generated `blueprint.yaml` as needed
    4. Prompt user for additional variables beyond the defaults that
       `forge init` provides
  - Reference: `forge-registry/references/blueprint-schema.md`,
    `forge-registry/references/conventions.md`
- [ ] Test scaffolding a new blueprint in an existing category (e.g.,
      `go/minimal`) and verify the output matches conventions
- [ ] Test scaffolding a new category (e.g., `python/`) and verify
      `_defaults/` structure is correct

#### Success Criteria

- A scaffolded blueprint (via `forge init`) passes `/registry-validate`
  with zero errors
- The generated `blueprint.yaml` matches yamlfmt formatting (document
  start marker, 2-space indent)
- Any post-scaffold adjustments (additional variables, template files)
  produce valid output referencing only declared variables
- A scaffolded category has `_defaults/` with `.gitignore` and
  `.claude/settings.json`

---

### Phase 4: Mutation Skills (blueprint-update, blueprint-add-template, blueprint-bump-version)

Deliver the three skills that modify existing blueprint files. These build on
the schema knowledge from the reference files and the validation logic from
Phase 2.

#### Tasks

- [ ] Create `.claude/skills/blueprint-update/SKILL.md` with:
  - Frontmatter: `name: blueprint-update`, description with trigger
    phrases
  - Trigger phrases: "add a variable to go/ext", "update the description
    of rust/std", "add a post_create hook", "change blueprint field"
  - Instructions to:
    1. Read the target `blueprint.yaml`
    2. Apply the requested change (add/remove/modify variables, update
       top-level fields, modify hooks/sync/rename)
    3. Validate the result against `blueprint-schema.md`
    4. Preserve yamlfmt formatting
  - Specific guidance for common operations:
    - Adding a variable: include all required subfields (name,
      description, type), prompt for validate/choices/default as
      appropriate
    - Removing a variable: warn if any `.tmpl` files reference it
    - Modifying hooks: preserve existing entries, append new ones
- [ ] Create `.claude/skills/blueprint-add-template/SKILL.md` with:
  - Frontmatter: `name: blueprint-add-template`, description with trigger
    phrases
  - Trigger phrases: "add a Makefile template to go/std", "create a CI
    workflow template", "add a template file"
  - Instructions to:
    1. Identify the target blueprint from `$ARGUMENTS`
    2. Determine placement: `_defaults/` (shared across category) vs
       blueprint-specific directory
    3. Create the `.tmpl` file with Go template placeholders
    4. Cross-reference declared variables in `blueprint.yaml` — warn if
       the template uses `{{ .var }}` for undeclared variables
    5. Suggest adding missing variables via `/blueprint-update`
  - Guidance on common template types: Makefile, CI workflow, config
    files, README
- [ ] Create `.claude/skills/blueprint-bump-version/SKILL.md` with:
  - Frontmatter: `name: blueprint-bump-version`, description with trigger
    phrases
  - Trigger phrases: "bump go/ext version", "bump all blueprints minor",
    "version bump", "release bump"
  - Instructions to:
    1. Parse current `version` from `blueprint.yaml` as semver
    2. Determine bump type from `$ARGUMENTS`: `major`, `minor`, `patch`
       (default: `patch`)
    3. Apply the bump and write back
    4. Support batch mode: bump all blueprints in a category, or all
       blueprints in the registry
    5. Output a summary table: blueprint name, old version, new version
- [ ] Test `/blueprint-update` by adding a variable to `go/std` and
      verifying the result
- [ ] Test `/blueprint-add-template` by adding a template to `rust/std`
      and verifying placeholder validation
- [ ] Test `/blueprint-bump-version` on a single blueprint and in batch
      mode

#### Success Criteria

- `/blueprint-update` produces valid YAML that passes `/registry-validate`
- `/blueprint-add-template` warns when a template references undeclared
  variables
- `/blueprint-bump-version patch` on a `0.1.0` blueprint produces `0.1.1`
- `/blueprint-bump-version minor` on a `0.1.0` blueprint produces `0.2.0`
- Batch bump across all go/ blueprints updates both `go/std` and `go/ext`

---

### Phase 5: Registry Reviewer Skill

Add a skill for reviewing blueprint changes. Since this is a local repo
(not a plugin), we implement this as a skill rather than an agent — it can
still be invoked via the Agent tool by the user or other skills.

#### Tasks

- [ ] Create `.claude/skills/registry-review/SKILL.md` with:
  - Frontmatter: `name: registry-review`, description with trigger
    phrases
  - Trigger phrases: "review blueprint changes", "check my blueprint PR",
    "review registry changes"
  - Instructions covering:
    1. Run `git diff` to find changed `blueprint.yaml` and `.tmpl` files
    2. Validate each changed `blueprint.yaml` against
       `blueprint-schema.md`
    3. Check template variable consistency (`.tmpl` files vs declared
       variables)
    4. Verify `_defaults/` inheritance (category defaults don't
       accidentally shadow registry defaults without reason)
    5. Confirm YAML formatting compliance
    6. Flag missing `rename:` for blueprints with `{{project_name}}/`
       directories
    7. Check that new blueprints include a `README.md.tmpl`
  - Reference: `forge-registry/references/blueprint-schema.md`,
    `forge-registry/references/conventions.md`
- [ ] Test the skill by reviewing the current registry state

#### Success Criteria

- `/registry-review` correctly identifies intentional validation issues
  when tested against a malformed blueprint
- Skill references the shared reference files (no duplicated
  schema/convention docs)
- Output is a clear checklist of pass/fail items with file paths

---

### Phase 6: Integration and Polish

Create `rust/_defaults/.claude/settings.json`, update CLAUDE.md, and do a
final validation pass.

#### Tasks

- [ ] Create `rust/_defaults/.claude/settings.json` mirroring the
      `go/_defaults/` pattern with appropriate Rust plugins enabled
- [ ] Update CLAUDE.md to document the available local skills and their
      slash commands
- [ ] Verify all skill SKILL.md files have valid YAML frontmatter
- [ ] Verify reference files are complete and referenced correctly
- [ ] Run `/registry-list` and `/registry-validate` against the full
      registry as a final smoke test
- [ ] Run `/registry-review` to confirm it produces useful output

#### Success Criteria

- `rust/_defaults/.claude/settings.json` exists with appropriate plugins
- CLAUDE.md documents all seven slash commands
- `/registry-list` returns correct data for all 5 blueprints
- `/registry-validate` reports clean against the current registry
- All skill files are discoverable via `/` command menu

---

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `.claude/skills/forge-registry/SKILL.md` | Create | Main skill entry point |
| `.claude/skills/forge-registry/references/blueprint-schema.md` | Create | blueprint.yaml schema ref |
| `.claude/skills/forge-registry/references/conventions.md` | Create | Registry conventions ref |
| `.claude/skills/registry-list/SKILL.md` | Create | List blueprints skill |
| `.claude/skills/registry-validate/SKILL.md` | Create | Validate registry skill |
| `.claude/skills/blueprint-scaffold/SKILL.md` | Create | Scaffold category/blueprint skill |
| `.claude/skills/blueprint-update/SKILL.md` | Create | Modify blueprint.yaml skill |
| `.claude/skills/blueprint-add-template/SKILL.md` | Create | Add .tmpl files skill |
| `.claude/skills/blueprint-bump-version/SKILL.md` | Create | Version bump skill |
| `.claude/skills/registry-review/SKILL.md` | Create | Review blueprint changes skill |
| `rust/_defaults/.claude/settings.json` | Create | Rust defaults with plugins enabled |
| `CLAUDE.md` | Modify | Document available skills |

## Testing Plan

- [ ] **Phase 1:** Verify SKILL.md frontmatter is valid and reference
      files cover all existing blueprints
- [ ] **Phase 2:** Run `/registry-list` and `/registry-validate` against
      the current registry and verify output accuracy
- [ ] **Phase 3:** Scaffold a test blueprint via `/blueprint-scaffold`,
      run `/registry-validate` on it, then clean up
- [ ] **Phase 4:** Exercise each mutation skill on a test blueprint and
      verify results with `/registry-validate`
- [ ] **Phase 5:** Introduce a known-bad blueprint and verify
      `/registry-review` catches the issues
- [ ] **Phase 6:** End-to-end smoke test of all seven skills

## Dependencies

- `forge` CLI — runtime dependency for `/blueprint-scaffold` (install via
  `mise install forge` if missing)
- `yamllint` — used by `/registry-validate`; available via mise
- `yamlfmt` — formatting reference for skills that write YAML

## Decisions

These questions from DESIGN-0001 have been resolved:

- **Plugin vs local skills:** Local skills in `.claude/skills/`. No plugin
  infrastructure needed — skills are available whenever Claude Code operates
  in this repo.
- **Rust defaults settings.json:** Yes — create it in Phase 6, mirroring
  the `go/_defaults/` pattern.
- **`forge init` vs direct scaffolding:** Use `forge init`. Always use the
  tool the same way a user would. Install via `mise install` if missing.
- **Root-level `std/` blueprint:** Include it — `std` is just a naming
  convention, not a special case.
- **Skill naming:** Use prefixed names to avoid collisions:
  `registry-list`, `registry-validate`, `registry-review`,
  `blueprint-scaffold`, `blueprint-update`, `blueprint-add-template`,
  `blueprint-bump-version`.
- **Batch operations:** Only `/blueprint-bump-version` supports batch mode
  for now. Extend to other mutation skills in a follow-up if useful.

## References

- [DESIGN-0001](../design/0001-claude-code-skills-for-forge-registry-management.md)
  — Claude Code Skills for Forge Registry Management
- Existing blueprints: `go/std`, `go/ext`, `rust/std`, `rust/esp32`, `std/`
- [Claude Code skills docs](https://code.claude.com/docs/en/skills) — local
  skills in `.claude/skills/`
