---
id: INV-0001
title: "Migrate remaining blueprints to forge v0.8 variable syntax and types"
status: Concluded
author: Donald Gifford
created: 2026-08-17
---

<!-- markdownlint-disable-file MD025 MD041 -->

# INV 0001: Migrate remaining blueprints to forge v0.8 variable syntax and types

**Status:** Concluded **Author:** Donald Gifford **Date:** 2026-08-17

<!--toc:start-->

- [Question](#question)
- [Hypothesis](#hypothesis)
- [Context](#context)
- [Approach](#approach)
- [Environment](#environment)
- [Findings](#findings)
  - [Observation 1: 18 of 19 blueprints fail to load under forge v0.8](#observation-1-18-of-19-blueprints-fail-to-load-under-forge-v08)
  - [Observation 2: what v0.8 rejects vs. tolerates](#observation-2-what-v08-rejects-vs-tolerates)
  - [Observation 3: registry-wide inventory of legacy constructs](#observation-3-registry-wide-inventory-of-legacy-constructs)
  - [Observation 4: the migrated pattern validates end to end](#observation-4-the-migrated-pattern-validates-end-to-end)
  - [Observation 5: syntax migration alone is not enough for 5 blueprints](#observation-5-syntax-migration-alone-is-not-enough-for-5-blueprints)
  - [Observation 6: structured-type supply channels constrain design](#observation-6-structured-type-supply-channels-constrain-design)
- [Conclusion](#conclusion)
- [Recommendation](#recommendation)
- [Open Questions](#open-questions)
  - [OQ-1 — Sequencing: syntax pass vs. #14 object consolidation](#oq-1--sequencing-syntax-pass-vs-14-object-consolidation)
  - [OQ-2 — git_provider default while migrating (forgejo is gone)](#oq-2--git_provider-default-while-migrating-forgejo-is-gone)
  - [OQ-3 — Fixing the 5 broken-surface blueprints](#oq-3--fixing-the-5-broken-surface-blueprints)
  - [OQ-4 — go/std backstage_tags (type = "map", dead, required)](#oq-4--gostd-backstage_tags-type--map-dead-required)
  - [OQ-5 — Version bump for migrated blueprints](#oq-5--version-bump-for-migrated-blueprints)
  - [OQ-6 — PR batching](#oq-6--pr-batching)
  - [OQ-7 — Drive-by fixes in the migration PRs](#oq-7--drive-by-fixes-in-the-migration-prs)
- [References](#references)
<!--toc:end-->

## Question

What is the exact scope of work required to make every blueprint in this
registry load and scaffold under forge v0.8, and is the migration purely
mechanical (search-and-replace per MIGRATION.md) or does it uncover structural
work beyond syntax?

## Hypothesis

The syntax conversion (`validate` regex → `validation` block, `choice` →
`string` + `contains()`, quoted type tags → bareword type expressions) is
mechanical and low-risk — go/k8s already proved the target shape. Suspected
non-mechanical remainder: blueprints whose variable surface doesn't cover the
templates they inherit from `_defaults/`, and the `git_provider` scalar cluster
that issue #14 wants collapsed into an `object({...})`.

## Context

forge v0.7 (IMPL-0009 / DESIGN-0006 in the forge repo) replaced the string-tag
variable type system with the cty type-expression grammar plus Terraform-style
`validation` blocks, and removed the legacy `choice`/`choices`/`validate` forms.
The installed forge is now v0.8, which enforces the removal at blueprint load
time. go/k8s was migrated to the new syntax when it was built (the first
v0.8-syntax blueprint); the other 18 blueprints still carry v0.6-era syntax and
are now un-loadable — `forge registry update` warns `missing` for every one of
them and `forge create` errors out. Per forge ADR-0002 there is no in-tool
migrator; the registry must be edited by hand.

**Triggered by:** forge v0.8.0 install + go/k8s work on `fix/go-k8s` (PR #17);
forge-registry issue #14; forge IMPL-0009 G.5.

## Approach

1. Inventory every `blueprint.hcl` (18 in scope) — verbatim variable blocks,
   hooks, conditions — and classify the legacy constructs.
2. Reproduce the v0.8 load failures against the real registry
   (`forge create go/ext`) and capture exact error messages.
3. Bisect what the loader rejects vs. tolerates by stripping one legacy
   construct at a time in a scratch copy of the registry (`/tmp/inv-reg`).
4. Fully migrate one representative blueprint (go/cli — it carries the whole
   pattern: regex validation, two choice enums, ternary cross-variable defaults,
   provider conditions) in the scratch copy and scaffold it end to end.
5. Map which `_defaults/` templates reference which variables, per inheritance
   level, to find blueprints whose variable surface can't render what they
   inherit.
6. Read forge `docs/MIGRATION.md` (variable type system upgrade section) and
   issue #14 for the sanctioned patterns and the object-migration direction.

## Environment

| Component      | Version / Value                                     |
| -------------- | --------------------------------------------------- |
| forge          | 0.8.0 (commit `806263d`)                            |
| forge-registry | branch `fix/go-k8s` @ `9360d4b`                     |
| Reference      | `go/k8s/blueprint.hcl` 0.2.0 (already v0.8 syntax)  |
| Scratch tests  | `rsync` copy at `/tmp/inv-reg`, scaffolds in `/tmp` |

## Findings

### Observation 1: 18 of 19 blueprints fail to load under forge v0.8

Only go/k8s loads. Every other blueprint dies at the first legacy construct the
decoder hits:

```text
$ forge create go/ext --registry-dir . --output-dir /tmp/x --set ...
Error: loading blueprint config: decoding blueprint file .../go/ext/blueprint.hcl:
variable "project_name": the `validate` regex field was removed in v0.7;
re-declare as a `validation { condition = can(regex("...", var.project_name))
error_message = "..." } block (see docs/MIGRATION.md#variable-type-system-upgrade-v07
```

`forge registry update` surfaces the same breakage as a wall of
`warning: <blueprint> missing` lines — it can only see go/k8s. Until migration
lands, the registry is effectively a single-blueprint registry for any consumer
on forge ≥ v0.7.

### Observation 2: what v0.8 rejects vs. tolerates

Bisected in the scratch registry, one construct at a time:

| Construct                      | v0.8 behavior                                     |
| ------------------------------ | ------------------------------------------------- |
| `validate = "<regex>"`         | **Load error** — points at MIGRATION.md           |
| `type = "choice"` + `choices`  | **Load error** — same pointer                     |
| `type = "string"` (quoted tag) | Loads (silent compat for quoted scalar tags)      |
| `type = "map"` (quoted tag)    | **Load error** — typeexpr: "primitive keyword or  |
|                                | complex type constructor call, like list(string)" |
| `type = int`                   | Deprecated alias for `number`, warns (no uses)    |

So the hard blockers are exactly the 26 `validate` occurrences, the 30 `choice`
variables, and go/std's `type = "map"`. Quoted `"string"` would limp along, but
the migration should move everything to bareword to match go/k8s and the
documented grammar.

### Observation 3: registry-wide inventory of legacy constructs

All 18 in-scope blueprints are at version 0.1.0 and use quoted type tags.
Constructs to convert: 26 `validate` regexes, 17 `license` choice enums, 13
`git_provider` choice enums, 39 ternary cross-variable defaults
(`"${git_provider == "forgejo" ? "x" : "y"}"`), 1 `"map"`.

The files fall into near-duplicate families — migrating one member migrates the
family:

| Family (identical bodies)               | Members | Legacy surface         |
| --------------------------------------- | ------- | ---------------------- |
| go/cli ≡ go/docker ≡ std/new            | 3       | full cluster + 2 enums |
| bun/std, std/docs (cluster variants)    | 2       | full cluster + 2 enums |
| homelab/{k8s,tf-modules,tf-live,images, | 7       | cluster + 2 enums      |
| charts,infra,docs}                      |         | (no owner/backstage)   |
| homelab/go (superset + go_version)      | 1       | cluster + 2 enums      |
| go/ext ≡ go/kubebuilder                 | 2       | validate + 1 enum      |
| rust/std ≡ rust/esp32                   | 2       | validate + 1 enum      |
| go/std (map outlier)                    | 1       | validate + `"map"`     |

"Full cluster" = `git_provider` + derived `project_org` / `git_host` /
`renovate_config_prefix` ternaries — the exact shape issue #14 proposes
collapsing into one `object({...})` variable.

### Observation 4: the migrated pattern validates end to end

go/cli was hand-migrated in the scratch registry: bareword types,
`validation { can(regex(...)) }`, `contains([...])` enums — ternary defaults and
`condition` blocks left untouched. Result:

- `forge create go/cli --set git_provider=github ...` → 40 files, `.forgejo/`
  excluded, `.github/` present.
- The ternary cross-variable defaults still evaluate: renovate.json5 rendered
  `github>donaldgifford/renovate-config`.
- Validation fires correctly: `--set git_provider=gitlab` →
  `Error: validating variables: git_provider must be one of: forgejo, github.`
  with file/line position.

Bare (non-`var.`-prefixed) references in ternary defaults and `condition.when`
need **no** changes — only the `variable` block internals change. For the 13
cluster blueprints the migration is confirmed mechanical.

### Observation 5: syntax migration alone is not enough for 5 blueprints

With go/ext's syntax fixed, scaffolding advances past loading and then fails
**rendering inherited `_defaults/` templates**:

```text
Error: writing file .forgejo/workflows/labels-sync.yml.tmpl: rendering
template .../_defaults/.forgejo/workflows/labels-sync.yml.tmpl:
Unknown variable; There is no variable named "git_host".
```

Root/category `_defaults/` templates reference variables that the no-cluster
blueprints never declare:

| Inherited template (level)                                      | Needs                                   |
| --------------------------------------------------------------- | --------------------------------------- |
| `_defaults/.forgejo/workflows/labels-sync.yml.tmpl`             | `git_host`                              |
| `_defaults/CONTRIBUTING.md.tmpl`                                | `git_host` + cluster                    |
| `_defaults/renovate.json5.tmpl` (+go/bun/std/homelab overrides) | `renovate_config_prefix`, `project_org` |
| `_defaults/catalog-info.yaml.tmpl` (+overrides)                 | `project_component_*`, cluster          |
| `_defaults/justfile.tmpl`                                       | `project_owner`                         |
| `_defaults/README.md.tmpl`, `go/_defaults/README.md.tmpl`       | `license`                               |
| `go/_defaults/go.mod.tmpl`, `go/_defaults/CLAUDE.md.tmpl`       | `git_host`                              |

Affected (blueprints that inherit at least one reference they cannot satisfy):
**go/std, go/ext, go/kubebuilder, rust/std, rust/esp32**. The 13 cluster
blueprints declare everything they inherit; homelab/\* is additionally safe
because `homelab/_defaults/` shadows the component/owner-referencing files with
variants that don't need them. go/k8s solved this same problem by declaring
pinned GitHub-default scalars plus a `defaults { exclude }` of the `.forgejo/`
tree.

Notable sub-findings:

- go/std's `backstage_tags` map has **zero** template consumers — it's a dead
  variable. go/std is also the only blueprint with no `license` variable while
  inheriting `README.md.tmpl` which renders `${license}`.
- These five blueprints were already broken on v0.6 for the same reason — the
  missing-variable render errors predate v0.8; the type migration merely
  re-surfaces them.

### Observation 6: structured-type supply channels constrain design

From forge MIGRATION.md and the v0.8 source (relevant to the #14 follow-up and
to go/std's map):

- `object({...})` variables prompt interactively as per-field prompts, accept
  `--set 'name={k="v",...}'` (quoted HCL literal), and work in var-files.
  Objects are first-class citizens in every channel.
- `list(T)` / `map(T)` are **var-file-only**: `--set` rejects them with a
  pointer error and interactive prompting can't collect them. A required map
  with no default (go/std's `backstage_tags` today) would make the blueprint
  impossible to scaffold without `--var-file`.
- Template refs traverse structured values natively: `${git_provider.org}` and
  `${var.git_provider.org}` both resolve.
- Lockfiles round-trip the new shapes; `forge sync` rewrites old lockfiles on
  first contact. No consumer-side action needed.

## Conclusion

**Answer: confirmed — with a known, bounded structural remainder.**

The v0.8 syntax migration is mechanical and empirically validated for the 14
blueprints whose variable surface is already complete (the 13 cluster
blueprints, pattern proven on go/cli; go/k8s already done). The remaining 5
(go/std, go/ext, go/kubebuilder, rust/std, rust/esp32) need variable-surface
reconciliation on top of the syntax swap, because they inherit `_defaults/`
templates that reference variables they never declare — a pre-existing break
that syntax migration exposes rather than causes. go/std additionally must shed
`type = "map"` (hard load error, dead variable). Nothing needs
`object`/`list`/`map` types to merely restore the registry; issue #14's object
consolidation is an optional second pass.

## Recommendation

Migrate in two passes: a mechanical syntax pass that restores a fully loadable
registry (fixing the 5 broken-surface blueprints with the proven go/k8s pattern
and flipping the `git_provider` default to `"github"`), then the issue #14
`git_provider` object consolidation as its own change. Pass 1 ships as one
registry-wide PR (per OQ-6), verifies every blueprint with a real `forge create`
scaffold, bumps each migrated blueprint 0.1.0 → 0.2.0 with a matching
`registry.hcl` sync, and carries the OQ-7 drive-by fixes. Decisions were
recorded 2026-08-18 under each open question below and feed the follow-up IMPL
doc.

## Open Questions

Answer format: pick a letter per question (a = recommendation), or write in your
own ("other").

**Decided 2026-08-18:** 1a, 2a, 3a, 4a, 5a, 6b, 7a.

### OQ-1 — Sequencing: syntax pass vs. #14 object consolidation

- **a (Recommended):** Two passes. Pass 1 migrates all 18 to v0.8 syntax as-is
  (restores the registry); pass 2 does the #14 `git_provider` → `object({...})`
  collapse on top. Each diff stays reviewable and pass 1 isn't blocked on
  object-shape decisions.
- b: One combined pass per blueprint — single touch per file, but every cluster
  blueprint's review carries both the mechanical swap and the object redesign
  (template refs, conditions, var-files all change).
- c: Syntax pass only; leave #14 unscheduled.

**Decision:** a — two passes; #14 follows as its own change.

### OQ-2 — `git_provider` default while migrating (forgejo is gone)

- **a (Recommended):** Flip the default to `"github"` during the syntax pass and
  keep `"forgejo"` in the allowed set. Matches the standing rule (GitHub is
  always the default); forgejo templates stay shippable for when it returns. Add
  `"gitlab"` only when real gitlab templates exist — an enum value with no
  `.gitlab/` tree behind it scaffolds broken repos.
- b: Keep `"forgejo"` as the default — pass 1 stays a pure syntax change with
  zero behavior delta.
- c: Flip to `"github"` and drop `"forgejo"` from the allowed set until it's
  back.

**Decision:** a — default flips to `"github"`; `"forgejo"` stays valid.

### OQ-3 — Fixing the 5 broken-surface blueprints

(go/std, go/ext, go/kubebuilder, rust/std, rust/esp32)

- **a (Recommended):** Apply the go/k8s pattern: declare pinned GitHub-default
  scalars (`project_org` defaulting to `"${project_owner}"`,
  `git_host = "github.com"`, `renovate_config_prefix = "github"`, plus the four
  `project_component_*` vars where catalog-info is inherited) and
  `defaults { exclude }` the `.forgejo/` tree. Small, proven, keeps the
  inherited renovate/catalog/README surface working.
- b: `defaults { exclude }` every inherited template that references an
  undeclared variable — smallest variable surface, but the scaffolds lose
  renovate config, catalog-info, CONTRIBUTING, etc.
- c: Give them the full 13-blueprint cluster (git_provider enum + ternary
  defaults + conditions) so every blueprint is provider- switchable — most
  uniform, but adds prompts these minimal blueprints never needed, and #14 would
  immediately reshape it again.

**Decision:** a — go/k8s pinned-defaults pattern + `.forgejo/` exclude.

### OQ-4 — go/std `backstage_tags` (`type = "map"`, dead, required)

- **a (Recommended):** Delete it and add the four `project_component_*` string
  variables used everywhere else. It has zero template consumers today, and a
  required map is var-file-only under v0.8 — keeping it makes go/std the only
  blueprint that can't be scaffolded interactively.
- b: Convert to `map(string)` with a `default = {}` — preserves the variable
  name for future use, stays optional, still var-file-only to override.
- c: Convert to `object({type, system, lifecycle, owner})` — promptable
  per-field and a working preview of the #14 pattern, but diverges from the
  scalar convention the other 17 blueprints use until #14 lands.

**Decision:** a — delete the map; add the four `project_component_*` scalars.

### OQ-5 — Version bump for migrated blueprints

- **a (Recommended):** Minor, 0.1.0 → 0.2.0 across all 18 — matches the go/k8s
  precedent (0.2.0 after its v0.8 work) and the supply surface genuinely changes
  (validation errors, enum enforcement).
- b: Patch, 0.1.0 → 0.1.1 — templates emitted are byte-identical for the
  pure-syntax blueprints, so treat it as internal.

**Decision:** a — 0.1.0 → 0.2.0 for all 18.

### OQ-6 — PR batching

- **a (Recommended):** Four family PRs: (1) go/std + go/ext + go/cli +
  go/docker + go/kubebuilder, (2) rust/std + rust/esp32, (3) bun/std + std/new +
  std/docs, (4) homelab/\* (8). Each PR scaffold-verifies its blueprints; a bad
  batch doesn't block the rest.
- b: One registry-wide PR — single review, single registry.hcl sync, but an
  18-blueprint diff.
- c: Per-blueprint PRs (18) — maximal isolation, mostly review overhead given
  the byte-identical families.

**Decision:** b — one registry-wide PR.

### OQ-7 — Drive-by fixes in the migration PRs

Candidates found during inventory: go/kubebuilder has no
`git init`/`go mod tidy` hooks (every other go blueprint has them); std/docs has
a duplicated `when = git_provider != "github"` condition and commented-out
hooks; homelab/go pins `go_version = "1.24"` vs `"1.26.4"` elsewhere;
registry.hcl keys are inconsistent (`go-std`, `go-kubebuilder` use dashes,
everything else slashes).

- **a (Recommended):** Include them — one-liners in files the migration already
  touches, and each family PR documents its own drive-bys.
- b: Strictly syntax-only; file an issue per item.

**Decision:** a — drive-bys ride the migration PR, called out in its
description.

## References

- forge `docs/MIGRATION.md` — "Variable type system upgrade (v0.7+)"
- forge DESIGN-0006 / IMPL-0009 — object and collection variable types
- forge ADR-0002 — no in-tool migrators
- forge-registry issue #14 — `git_provider` object consolidation (IMPL-0009 G.5
  follow-up)
- `go/k8s/blueprint.hcl` — reference v0.8-syntax blueprint
- [docs/examples/README.md](../examples/README.md) — var-file semantics and
  structured-type supply channels
- DESIGN-0004 / IMPL-0002 — go/k8s blueprint (established the pinned
  GitHub-defaults + `defaults { exclude }` pattern)
