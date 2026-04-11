---
name: registry-review
description: >
  Review blueprint changes for correctness and convention compliance. Use
  when reviewing PRs that modify blueprints, checking changes before
  committing, or validating recent edits. Triggers on: "review blueprint
  changes", "check my blueprint PR", "review registry changes".
---

# Registry Review

Review blueprint changes in the current git diff for correctness,
convention compliance, and consistency.

## Process

### 1. Identify Changed Files

```bash
# Staged and unstaged changes
git diff --name-only HEAD
git diff --name-only --cached

# Or for PR review against main
git diff --name-only main...HEAD
```

Focus on: `blueprint.yaml`, `.tmpl` files, `_defaults/` files.

### 2. Validate Changed blueprint.yaml Files

For each changed `blueprint.yaml`:

- [ ] **Required fields** present: `apiVersion`, `name`, `description`,
      `version`
- [ ] **Document start marker** `---` present
- [ ] **Variables** well-formed:
  - All have `name`, `description`, `type`
  - Choice variables have `choices` list
  - Validate regexes are valid
- [ ] **Name convention** matches `<category>-<name>`
- [ ] **Version** is valid semver

### 3. Check Template Variable Consistency

For each changed `.tmpl` file, extract `{{ .var }}` references and verify
they match declared variables in the corresponding `blueprint.yaml`:

```bash
grep -oP '\{\{\s*\.\K[a-zA-Z_][a-zA-Z0-9_]*' <file>.tmpl | sort -u
```

Check variables against:
1. The blueprint's own `blueprint.yaml`
2. The category `_defaults/` (variables may be inherited)

Flag any undeclared variable references.

### 4. Verify `_defaults/` Inheritance

If `_defaults/` files were changed:

- [ ] Category defaults don't accidentally shadow registry defaults
      without good reason
- [ ] New files in `_defaults/` follow naming conventions
- [ ] `.claude/settings.json` changes are intentional

### 5. Confirm YAML Formatting

```bash
yamllint -c .yamllint.yml <changed-yaml-files>
```

Report warnings and errors.

### 6. Check Rename Mappings

For blueprints with `{{project_name}}/` directories:

- [ ] `rename:` entry exists mapping `"{{project_name}}/"` to `"."`

### 7. New Blueprint Checklist

If a new blueprint was added:

- [ ] Has a `README.md.tmpl` (or inherits one from `_defaults/`)
- [ ] `blueprint.yaml` follows the schema
- [ ] At minimum defines a `project_name` variable

## Output Format

```
Registry Review
===============

Changed files:
  - go/ext/blueprint.yaml (modified)
  - go/ext/{{project_name}}/README.md.tmpl (modified)

Checks:
  [PASS] go/ext: Required fields present
  [PASS] go/ext: Document start marker present
  [PASS] go/ext: Variables well-formed
  [PASS] go/ext: Template variables match declarations
  [PASS] go/ext: YAML lint clean
  [PASS] go/ext: Rename mapping present

Summary: 6 passed, 0 warnings, 0 failures
```

## References

- [blueprint-schema.md](../forge-registry/references/blueprint-schema.md) —
  schema validation rules
- [conventions.md](../forge-registry/references/conventions.md) — formatting
  and naming conventions
