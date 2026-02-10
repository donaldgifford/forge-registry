# forge-registry

Forge Registry

## Structure

```
├── registry.yaml        # Registry index
├── _defaults/           # Registry-wide default files
│   ├── .editorconfig
│   └── .gitignore
└── <category>/
    └── _defaults/       # Category-level default files
```

## Adding a Blueprint

```bash
forge init <category>/<name> --registry .
```
