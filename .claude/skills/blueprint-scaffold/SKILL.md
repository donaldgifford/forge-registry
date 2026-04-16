---
name: blueprint-scaffold
description: >
  Scaffold a new blueprint or category in the forge registry using the forge
  CLI. Use when creating a new blueprint, adding a blueprint to an existing
  category, or creating a new category. Triggers on: "create a new blueprint",
  "add a go blueprint", "scaffold rust/embedded", "new category python".
---

# Blueprint Scaffold

Create new categories and blueprints in the forge registry.

## Prerequisites

The `forge` CLI must be installed. If not available, install via mise:

```bash
mise install forge
```

## Decision: Category or Blueprint?

Determine from the user's request:

- **New category** — the `<category>/` directory does not exist yet
- **New blueprint** — the `<category>/` directory already exists

Check with:

```bash
ls -d <category>/ 2>/dev/null
```

## New Category Workflow

When creating an entirely new category (e.g., `python`):

1. **Create the category defaults directory:**

   ```bash
   mkdir -p <category>/_defaults/.claude
   ```

2. **Create `<category>/_defaults/.gitignore`** — copy the pattern from an
   existing category (e.g., `go/_defaults/.gitignore`) and adjust for the
   new language.

3. **Create `<category>/_defaults/.claude/settings.json`** with baseline
   plugins:

   ```json
   {
     "enabledPlugins": {
       "ralph-loop@claude-plugins-official": true,
       "claude-md@donaldgifford-claude-skills": true,
       "docker@donaldgifford-claude-skills": true,
       "makefiles@donaldgifford-claude-skills": true,
       "mise@donaldgifford-claude-skills": true,
       "shell-scripting@donaldgifford-claude-skills": true,
       "docz@donaldgifford-claude-skills": true
     }
   }
   ```

   Add language-specific plugins as appropriate.

4. **Ask the user** about category-level tooling: language version manager,
   build tool, CI workflows, linter config.

5. **Create the first blueprint** using the blueprint workflow below.

## New Blueprint Workflow

When adding a blueprint to an existing (or just-created) category:

1. **Run `forge init`:**

   ```bash
   forge init <category>/<name> --registry .
   ```

   This scaffolds the blueprint directory with a `blueprint.yaml` and
   basic structure. Follow the interactive prompts.

2. **Review the generated `blueprint.yaml`** and ensure it has:
   - `---` document start marker
   - `apiVersion: v1`
   - Name following `<category>-<name>` convention
   - At minimum a `project_name` variable (string, required)
   - `version: "0.1.0"`
   - `sync:` with empty `managed_files` and `ignore`
   - `rename:` mapping `"{{project_name}}/"` to `"."` (if applicable)

3. **Ask the user** about additional variables beyond what `forge init`
   provides. For each variable, determine:
   - Type: `string` or `choice`
   - Whether validation regex is needed
   - Whether a default value is appropriate

4. **Create `{{project_name}}/README.md.tmpl`** if not already present:

   ```markdown
   # {{ .project_name }}

   {{ .project_description }}
   ```

## Post-Scaffold Validation

After scaffolding, run `/registry-validate` mentally or suggest the user
run it to confirm the new blueprint is structurally correct.

## References

- [blueprint-schema.md](../forge-registry/references/blueprint-schema.md) —
  field requirements and variable types
- [conventions.md](../forge-registry/references/conventions.md) — naming,
  directory structure, YAML formatting
