# Registry Conventions

## Three-Tier Inheritance Model

```
_defaults/              -> Registry-wide defaults (all categories inherit)
<category>/_defaults/   -> Category-level defaults (override registry defaults)
<category>/<name>/      -> Blueprint-specific files (highest priority)
```

Files at lower tiers override files at higher tiers with the same path.
For example, `go/_defaults/.gitignore` overrides `_defaults/.gitignore` for
all Go blueprints.

## Directory Structure

```
_defaults/                          # Registry-wide defaults
├── .gitignore
├── .markdownlint.yaml
├── .prettierrc.yaml
├── .claude/settings.json
go/                                 # Category: Go
├── _defaults/                      # Shared Go defaults
│   ├── .golangci.yml
│   ├── Makefile.tmpl
│   ├── mise.toml.tmpl
│   └── .claude/settings.json
├── std/                            # Blueprint: go-std
│   └── blueprint.yaml
└── ext/                            # Blueprint: go-ext
    ├── blueprint.yaml
    └── {{project_name}}/
        └── README.md.tmpl
rust/                               # Category: Rust
├── _defaults/                      # Shared Rust defaults
│   ├── Makefile
│   ├── Cargo.toml
│   └── mise.toml.tmpl
├── std/                            # Blueprint: rust-std
│   ├── blueprint.yaml
│   └── {{project_name}}/
│       └── README.md.tmpl
└── esp32/                          # Blueprint: rust-esp32
    ├── blueprint.yaml
    └── {{project_name}}/
        └── README.md.tmpl
std/                                # Root-level blueprint (no category)
└── blueprint.yaml
```

## Naming Conventions

- **Category directories:** lowercase, hyphenated (e.g., `go`, `rust`)
- **Blueprint directories:** lowercase, hyphenated (e.g., `std`, `ext`,
  `esp32`)
- **Blueprint names:** `<category>-<name>` (e.g., `go-ext`, `rust-std`)
- **Root-level blueprints:** name matches directory (e.g., `std`)

## Template Syntax

Two different syntaxes are used depending on context:

### File contents (`.tmpl` files)

Go template syntax with spaces and dot prefix:

```
{{ .project_name }}
{{ .project_owner }}
{{ .project_description }}
```

### Directory names

No spaces, no dot prefix:

```
{{project_name}}/
```

This maps to a `rename:` entry in `blueprint.yaml`:

```yaml
rename:
  "{{project_name}}/": "."
```

## YAML Formatting

- **Document start marker:** `---` (required by yamllint config)
- **Indentation:** 2 spaces
- **Line length:** max 120 characters (warning level)
- **Empty values:** forbidden in block/flow mappings
- **Formatter:** yamlfmt with `include_document_start: true`

Note: Some existing blueprints (`go/std`, `rust/std`, `rust/esp32`, `std/`)
are missing the `---` document start marker — this is a known inconsistency.

## `.tmpl` Extension Convention

- Files that contain Go template placeholders use the `.tmpl` extension
- The extension is stripped during blueprint creation (e.g.,
  `Makefile.tmpl` becomes `Makefile`)
- Files without template placeholders do not need the `.tmpl` extension

## `_defaults/.claude/settings.json` Pattern

Each category's `_defaults/` should include a `.claude/settings.json` with
plugins appropriate for that language:

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

Go blueprints add: `go-development`, `gopls-lsp`, `systems-programming`,
`skill-creator`.

## Rename Mapping

The `rename:` field maps template directory names to output paths:

```yaml
rename:
  "{{project_name}}/": "."
```

Every blueprint that has a `{{project_name}}/` directory must have a
corresponding `rename:` entry. The `.` target means the directory contents
are placed at the project root.
