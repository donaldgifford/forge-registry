---
name: blueprint-bump-version
description: >
  Bump the semver version of one or more blueprints in the forge registry.
  Use when bumping versions, releasing blueprints, or doing batch version
  updates. Triggers on: "bump go/ext version", "bump all blueprints minor",
  "version bump", "release bump".
---

# Blueprint Bump Version

Bump the semantic version of blueprints.

## Process

1. **Determine scope** from `$ARGUMENTS` or user request:
   - **Single blueprint:** `<category>/<name>` (e.g., `go/ext`)
   - **Category batch:** `<category>` (e.g., `go` — bumps all blueprints
     in the category)
   - **Registry batch:** `all` — bumps every blueprint in the registry

2. **Determine bump type:**
   - `major` — X.0.0 (breaking changes)
   - `minor` — x.Y.0 (new features)
   - `patch` — x.y.Z (bug fixes, default)

   If not specified, default to `patch`.

3. **For each target blueprint:**

   a. Read `blueprint.yaml` and parse the current `version` field.

   b. Apply the semver bump:
      - `0.1.0` + patch = `0.1.1`
      - `0.1.0` + minor = `0.2.0`
      - `0.1.0` + major = `1.0.0`

   c. Update the `version` field in `blueprint.yaml`.

   d. Preserve all other fields and formatting (document start marker,
      indentation, quoting style).

4. **Output a summary table:**

   ```
   | Blueprint | Old Version | New Version |
   |-----------|-------------|-------------|
   | go/ext    | 0.1.0       | 0.1.1       |
   | go/std    | 0.1.0       | 0.1.1       |
   ```

## Examples

```
# Single blueprint patch bump
/blueprint-bump-version go/ext patch

# All Go blueprints minor bump
/blueprint-bump-version go minor

# Entire registry patch bump
/blueprint-bump-version all patch
```

## Finding Blueprints

```bash
# All blueprints
find . -name blueprint.yaml -not -path '*/_defaults/*' -not -path './.git/*'

# Blueprints in a category
find ./<category>/ -name blueprint.yaml -not -path '*/_defaults/*'
```

## References

- [blueprint-schema.md](../forge-registry/references/blueprint-schema.md) —
  version field specification
