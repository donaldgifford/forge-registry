---
name: registry-validate
description: >
  Validate the forge registry structure and blueprint definitions. Use when
  validating blueprints, linting the registry, or checking blueprint
  structure. Triggers on: "validate the registry", "lint blueprints",
  "check blueprint structure".
---

# Registry Validate

Validate all blueprints in the registry for structural correctness, schema
compliance, and template consistency.

## Validation Checklist

Run each check against every blueprint. Report results as a pass/fail list
with file paths for any failures.

### 1. Required Fields

Every `blueprint.yaml` must have: `apiVersion`, `name`, `description`,
`version`.

```bash
# For each blueprint.yaml, verify these fields exist and are non-empty
```

### 2. Choice Variables Have Choices

Any variable with `type: choice` must have a non-empty `choices` list.

### 3. Validate Regex Is Valid

Any variable with a `validate` field must contain a valid regular expression.
Test by attempting to compile the regex.

### 4. Template Variable Consistency

Every `{{ .var }}` reference in `.tmpl` files must correspond to a variable
declared in the blueprint's (or category defaults') `blueprint.yaml`.

```bash
# Extract template variables from .tmpl files
grep -oP '\{\{\s*\.\K[a-zA-Z_][a-zA-Z0-9_]*' *.tmpl

# Compare against declared variables in blueprint.yaml
```

Walk up the inheritance chain: check the blueprint's own `blueprint.yaml`
first, then `<category>/_defaults/` blueprint variables if any.

### 5. Rename Mapping for Template Directories

Every blueprint directory containing a `{{project_name}}/` (or similar
template-named) subdirectory must have a corresponding `rename:` entry in
its `blueprint.yaml`.

### 6. YAML Lint Compliance

Run `yamllint` against all YAML files if available:

```bash
yamllint -c .yamllint.yml <file>
```

Report warnings and errors separately.

## Output Format

```
Registry Validation Report
==========================

[PASS] go/std: Required fields present
[PASS] go/std: No choice variables to validate
[PASS] go/std: No validate regexes to check
[PASS] go/std: No .tmpl files to check
[WARN] go/std: No rename mapping (no template directories found)
[PASS] go/std: YAML lint clean

[PASS] go/ext: Required fields present
[PASS] go/ext: Choice variable 'license' has choices
...

Summary: X passed, Y warnings, Z failures
```

## References

- [blueprint-schema.md](../forge-registry/references/blueprint-schema.md) —
  field requirements and types
- [conventions.md](../forge-registry/references/conventions.md) — YAML
  formatting rules and template syntax
