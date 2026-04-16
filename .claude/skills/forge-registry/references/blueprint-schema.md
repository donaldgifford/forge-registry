# Blueprint Schema Reference

Every blueprint is defined by a `blueprint.yaml` file in its directory.

## Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `apiVersion` | string | Always `v1` |
| `name` | string | Unique blueprint identifier (e.g., `go-ext`, `rust-std`) |
| `description` | string | Human-readable description |
| `version` | string | Semver version (e.g., `"0.1.0"`) |

## Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `tags` | list of strings | Searchable tags (e.g., `["go", "extended"]`) |
| `variables` | list of variable objects | User-prompted inputs |
| `hooks` | object | Lifecycle hooks |
| `sync` | object | Sync configuration |
| `rename` | object | Directory rename mappings |

## Variable Object

Each variable in the `variables` list has these fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Variable identifier used in templates as `{{ .name }}` |
| `description` | string | yes | Prompt shown to the user |
| `type` | string | yes | `string` or `choice` |
| `required` | boolean | no | Whether the variable must be provided (default: false) |
| `validate` | string | no | Regex pattern for validation (string type only) |
| `choices` | list of strings | no | Valid options (choice type only, required when type is choice) |
| `default` | string | no | Default value |

## Hooks Object

```yaml
hooks:
  post_create:
    - "git init"
    - "make setup"
```

- `post_create` — list of shell commands run after blueprint creation

## Sync Object

```yaml
sync:
  managed_files: []
  ignore: []
```

- `managed_files` — files managed by forge sync (kept in sync with registry)
- `ignore` — files excluded from sync operations

## Rename Object

```yaml
rename:
  "{{project_name}}/": "."
```

Maps template directory names to their output location. The key uses
`{{variable_name}}` syntax (no spaces, no dot prefix). The value is the
target path (`.` means project root).

## Annotated Examples

### Minimal blueprint (`go/std`)

```yaml
apiVersion: v1
name: "go-std"
description: "Go Standard Repo"
version: "0.1.0"
tags: ["go-std"]

variables:
  - name: project_name
    description: "Name of the project"
    type: string
    required: true
```

No hooks, sync, or rename — simplest possible blueprint.

### Extended blueprint (`go/ext`)

```yaml
---
apiVersion: v1
name: "go-ext"
description: "Go extended blueprint"
version: "0.1.0"
tags: ["go", "extended", "makefile"]

variables:
  - name: project_name
    description: "Name of the project"
    type: string
    required: true
    validate: "^[a-z][a-z0-9-]*$"

  - name: project_owner
    description: "Owner of the project"
    type: string
    required: true
    validate: "^[a-z][a-z0-9-]*$"

  - name: project_description
    description: "Description of the project"
    type: string
    required: true

  - name: license
    description: "License type"
    type: choice
    choices: ["MIT", "Apache-2.0", "BSD-3-Clause", "none"]
    default: "Apache-2.0"

sync:
  managed_files: []
  ignore: []

rename:
  "{{project_name}}/": "."
```

Demonstrates: validation regex, choice type with default, sync, and rename.

### Blueprint with hooks (`rust/std`)

```yaml
apiVersion: v1
name: "rust-std"
description: "Rust Standard Repo"
version: "0.1.0"
tags: ["rust", "std"]

variables:
  - name: project_name
    description: "Name of the project"
    type: string
    required: true
    validate: "^[a-z][a-z0-9-]*$"

  - name: license
    description: "License type"
    type: choice
    choices: ["MIT", "Apache-2.0", "BSD-3-Clause", "none"]
    default: "Apache-2.0"

hooks:
  post_create:
    - "git init"

sync:
  managed_files: []
  ignore: []

rename:
  "{{project_name}}/": "."
```

Demonstrates: post_create hooks for initialization commands.
