---
name: registry-list
description: >
  List all blueprints in the forge registry with metadata. Use when listing
  blueprints, checking what exists, showing registry status. Triggers on:
  "list blueprints", "what blueprints exist", "show go blueprints",
  "registry status".
---

# Registry List

List all blueprints in the forge registry with their metadata.

## Process

1. Find all `blueprint.yaml` files in the registry (exclude `_defaults/`
   directories):

   ```bash
   find . -name blueprint.yaml -not -path '*/_defaults/*' -not -path './.git/*'
   ```

2. For each blueprint, parse the YAML and extract:
   - **Category**: parent directory name, or `(root)` if at repo root level
   - **Name**: the `name` field from blueprint.yaml
   - **Version**: the `version` field
   - **Variables**: count of items in the `variables` list
   - **Tags**: the `tags` list joined with commas

3. If `$ARGUMENTS` specifies a category (e.g., `go`), filter to only
   blueprints under that category directory.

4. Output as a markdown table:

   ```
   | Category | Name | Version | Variables | Tags |
   |----------|------|---------|-----------|------|
   | go | go-std | 0.1.0 | 1 | go-std |
   | go | go-ext | 0.1.0 | 4 | go, extended, makefile |
   | rust | rust-std | 0.1.0 | 2 | rust, std |
   | rust | rust-esp32 | 0.1.0 | 2 | rust, esp32 |
   | (root) | std | 0.1.0 | 1 | |
   ```

## Reference

For schema details, see
[forge-registry/references/blueprint-schema.md](../forge-registry/references/blueprint-schema.md).
