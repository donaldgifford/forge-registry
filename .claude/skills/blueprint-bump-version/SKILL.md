---
name: blueprint-bump-version
description: >
  Bump the semver version of one or more blueprints in the forge registry. Use
  when bumping versions, releasing blueprints, or doing batch version updates.
  Triggers on: "bump go/ext version", "bump all blueprints minor", "version
  bump", "release bump".
---

# Blueprint Bump Version

Bump the semantic version of blueprints in `blueprint.hcl`.

## Do not hand-edit the version

`scripts/bump-blueprint.sh` owns this. It parses the current version, applies
the bump, and rewrites only the quoted value on the `version` line so the
alignment survives and the diff is one line. It is covered by
`scripts/test/bump-blueprint.bats`.

```bash
scripts/bump-blueprint.sh <category>/<name> <major|minor|patch>
```

Reach for the script for every bump, including batches — loop over it rather
than editing files directly.

## Why the bump is mandatory

Consumers pin a blueprint by `version`. Changing template files without bumping
hands people different output under a version they already resolved. CI enforces
it: the `Blueprint Version Gate` job runs `scripts/check-blueprint-bump.sh`,
which fails the PR naming every blueprint that changed without a bump.

Run the gate to find out what is owed rather than reasoning about it:

```bash
scripts/check-blueprint-bump.sh
```

It accounts for inheritance fan-out, which is easy to get wrong by hand. A
change under the registry root `_defaults/` obligates all 19 blueprints; a
change under `<category>/_defaults/` obligates that category's blueprints.

## Process

1. **Determine scope** from `$ARGUMENTS` or the user request:
   - **Single blueprint:** `<category>/<name>` (e.g. `go/ext`)
   - **Category batch:** `<category>` (e.g. `go`)
   - **Registry batch:** `all`

   If the user is bumping because of an edit they just made, prefer running
   `scripts/check-blueprint-bump.sh` and bumping exactly what it names.

2. **Determine bump level** by what a consumer would notice:
   - `major` — required variables change, files removed, output restructured
   - `minor` — new variable, new template file, new capability
   - `patch` — typo, dependency bump, non-behavioural fix

   Default to `patch` when unspecified.

3. **Run the script once per blueprint.** For a category or registry batch:

   ```bash
   for bp in $(git ls-files -- '<category>/*/blueprint.hcl' \
     | sed 's|/blueprint.hcl$||'); do
     scripts/bump-blueprint.sh "$bp" patch
   done
   ```

   Drop the `<category>/` prefix for `all`. Note the glob matches
   `<category>/<name>/blueprint.hcl` only, so `_defaults/` directories are
   excluded already.

4. **Output a summary table:**

   ```text
   | Blueprint | Old Version | New Version |
   | --------- | ----------- | ----------- |
   | go/ext    | 0.1.0       | 0.1.1       |
   | go/std    | 0.1.0       | 0.1.1       |
   ```

5. **Remind about the release label.** The bump alone does not release anything.
   The PR needs one of `major`, `minor`, `patch`, or `dont-release`, and the
   release job reads that label — not the blueprint versions — to decide the
   registry tag. A blueprint change labelled `dont-release` is rejected.

## Examples

```text
# Single blueprint patch bump
/blueprint-bump-version go/ext patch

# All Go blueprints minor bump
/blueprint-bump-version go minor

# Entire registry patch bump
/blueprint-bump-version all patch
```

## Finding blueprints

```bash
# All blueprints
git ls-files -- '*/*/blueprint.hcl' | sed 's|/blueprint.hcl$||'

# Blueprints in a category
git ls-files -- '<category>/*/blueprint.hcl' | sed 's|/blueprint.hcl$||'
```

## References

- [CONTRIBUTING.md](../../../CONTRIBUTING.md) — release labels and the PR
  lifecycle
- [blueprint-schema.md](../forge-registry/references/blueprint-schema.md) —
  version field specification
