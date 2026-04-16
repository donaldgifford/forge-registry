---
name: blueprint-update
description: >
  Modify blueprint.yaml fields in the forge registry. Use when adding or
  removing variables, updating descriptions, changing hooks, or modifying
  sync/rename configuration. Triggers on: "add a variable to go/ext",
  "update the description of rust/std", "add a post_create hook",
  "change blueprint field".
---

# Blueprint Update

Modify fields in an existing blueprint's `blueprint.yaml`.

## Process

1. **Identify the target blueprint** from the user's request. Resolve the
   path: `<category>/<name>/blueprint.yaml`.

2. **Read the current `blueprint.yaml`** in full before making changes.

3. **Apply the requested change** — see Common Operations below.

4. **Validate the result** against the schema:
   - Required fields still present (`apiVersion`, `name`, `description`,
     `version`)
   - Choice variables have `choices` list
   - Validate regexes compile
   - No orphaned template references

5. **Preserve formatting:**
   - `---` document start marker
   - 2-space indentation
   - Consistent quoting style (match existing)

## Common Operations

### Adding a Variable

Include all required subfields:

```yaml
- name: new_variable
  description: "Description shown to user"
  type: string        # or "choice"
  required: true      # optional, default false
  validate: "^[a-z]+$"  # optional, string type only
```

For choice variables, add `choices` and optional `default`:

```yaml
- name: license
  description: "License type"
  type: choice
  choices: ["MIT", "Apache-2.0", "BSD-3-Clause", "none"]
  default: "Apache-2.0"
```

### Removing a Variable

Before removing, check if any `.tmpl` files reference `{{ .variable_name }}`:

```bash
grep -r '{{ *\.variable_name' <category>/<name>/ <category>/_defaults/
```

Warn the user if references exist — they must be updated or removed first.

### Modifying Hooks

Preserve existing entries and append new ones:

```yaml
hooks:
  post_create:
    - "git init"          # existing
    - "make setup"        # new
```

### Updating Top-Level Fields

Simply replace the value. Keep quoting consistent with the rest of the file.

## References

- [blueprint-schema.md](../forge-registry/references/blueprint-schema.md) —
  full field reference and examples
