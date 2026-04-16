---
name: blueprint-add-template
description: >
  Add template files (.tmpl) to a blueprint in the forge registry. Use when
  adding Makefile templates, CI workflow templates, config templates, or
  README templates. Triggers on: "add a Makefile template to go/std",
  "create a CI workflow template", "add a template file".
---

# Blueprint Add Template

Add `.tmpl` files to a blueprint or its category defaults.

## Process

1. **Identify the target** from `$ARGUMENTS` or user context:
   - Blueprint path: `<category>/<name>/`
   - Or category defaults: `<category>/_defaults/`

2. **Determine placement:**
   - **`_defaults/`** — if the file should be shared across all blueprints
     in the category (e.g., Makefile, CI workflows, linter config)
   - **Blueprint directory** — if the file is specific to one blueprint
     (e.g., blueprint-specific README)

3. **Create the `.tmpl` file** with Go template placeholders:
   - Use `{{ .variable_name }}` syntax (spaces inside braces, dot prefix)
   - Only reference variables declared in the blueprint's `blueprint.yaml`

4. **Cross-reference variables:**

   After creating the template, verify all placeholders match declared
   variables:

   ```bash
   # Extract variables used in the template
   grep -oP '\{\{\s*\.\K[a-zA-Z_][a-zA-Z0-9_]*' <file>.tmpl | sort -u

   # Compare against blueprint.yaml variables
   ```

   If the template references undeclared variables:
   - **Warn the user** with the list of undeclared variables
   - **Suggest** running `/blueprint-update` to add the missing variables

## Common Template Types

### Makefile (`Makefile.tmpl`)

```makefile
PROJECT_NAME := {{ .project_name }}
```

Place in `_defaults/` if shared across category.

### CI Workflow (`.github/workflows/ci.yml`)

Usually not templated (no `.tmpl` extension) unless it references project
variables. Place in `_defaults/.github/workflows/`.

### README (`README.md.tmpl`)

```markdown
# {{ .project_name }}

{{ .project_description }}
```

Place in `<blueprint>/{{project_name}}/` directory.

### Config Files

Language-specific config (`.golangci.yml`, `clippy.toml`, etc.) usually go
in `_defaults/` without the `.tmpl` extension unless they need variable
substitution.

## References

- [blueprint-schema.md](../forge-registry/references/blueprint-schema.md) —
  variable types and template syntax
- [conventions.md](../forge-registry/references/conventions.md) — .tmpl
  extension rules, directory placement
