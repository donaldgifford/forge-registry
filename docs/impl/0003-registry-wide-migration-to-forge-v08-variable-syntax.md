---
id: IMPL-0003
title: "Registry-wide migration to forge v0.8 variable syntax"
status: In Progress
author: Donald Gifford
created: 2026-08-18
---

<!-- markdownlint-disable-file MD024 MD025 MD041 -->

# IMPL 0003: Registry-wide migration to forge v0.8 variable syntax

**Status:** In Progress **Author:** Donald Gifford **Date:** 2026-08-18

<!--toc:start-->

- [Objective](#objective)
- [Scope](#scope)
  - [In Scope](#in-scope)
  - [Out of Scope](#out-of-scope)
- [Verified Forge Behavior](#verified-forge-behavior)
- [Implementation Phases](#implementation-phases)
  - [Phase 1: Cluster-family syntax migration (13 blueprints)](#phase-1-cluster-family-syntax-migration-13-blueprints)
    - [Tasks](#tasks)
    - [Success Criteria](#success-criteria)
  - [Phase 2: Surface reconciliation — go/ext, go/kubebuilder, rust/std, rust/esp32](#phase-2-surface-reconciliation--goext-gokubebuilder-ruststd-rustesp32)
    - [Tasks](#tasks-1)
    - [Success Criteria](#success-criteria-1)
  - [Phase 3: go/std rebuild](#phase-3-gostd-rebuild)
    - [Tasks](#tasks-2)
    - [Success Criteria](#success-criteria-2)
  - [Phase 4: Registry metadata, drive-bys, and docs](#phase-4-registry-metadata-drive-bys-and-docs)
    - [Tasks](#tasks-3)
    - [Success Criteria](#success-criteria-3)
  - [Phase 5: Full-registry verification and landing](#phase-5-full-registry-verification-and-landing)
    - [Tasks](#tasks-4)
    - [Success Criteria](#success-criteria-4)
  - [Phase 6: Pass-2 semantics validation (scratch)](#phase-6-pass-2-semantics-validation-scratch)
    - [Tasks](#tasks-5)
    - [Findings](#findings)
    - [Success Criteria](#success-criteria-5)
  - [Phase 7: Pass-2 object migration (all 19 blueprints + shared templates)](#phase-7-pass-2-object-migration-all-19-blueprints--shared-templates)
    - [Tasks](#tasks-6)
    - [Findings](#findings-1)
    - [Success Criteria](#success-criteria-6)
  - [Phase 8: Pass-2 verification and landing](#phase-8-pass-2-verification-and-landing)
    - [Tasks](#tasks-7)
    - [Success Criteria](#success-criteria-7)
- [File Changes](#file-changes)
- [Testing Plan](#testing-plan)
- [Open Questions](#open-questions)
  - [1. Branch base for the migration PR](#1-branch-base-for-the-migration-pr)
  - [2. Backstage component variables in the 5 reconciled blueprints](#2-backstage-component-variables-in-the-5-reconciled-blueprints)
  - [3. Smoke-verification harness](#3-smoke-verification-harness)
  - [4. Pass-2 (#14 object consolidation) planning](#4-pass-2-14-object-consolidation-planning)
- [Dependencies](#dependencies)
- [References](#references)

<!--toc:end-->

## Objective

Migrate the 18 unmigrated blueprints to the forge v0.8 variable syntax so the
whole registry loads and scaffolds again (today only go/k8s does), fix the five
blueprints whose variable surface can't render the `_defaults/` templates they
inherit, and land it all as one registry-wide PR. Phases 1–5 are **pass 1** from
INV-0001. Phases 6–8 plan **pass 2** — the issue #14 `git_provider` object
consolidation — which ships as its own PR after pass 1 merges (OQ-4b: one doc
for the whole v0.8 story, two PRs).

**Implements:** INV-0001 (decisions 1a, 2a, 3a, 4a, 5a, 6b, 7a)

## Scope

### In Scope

- Syntax conversion in all 18 `blueprint.hcl` files: bareword types, `validate`
  regex → `validation { can(regex(...)) }`, `choice`/ `choices` → `string` +
  `contains()` validation (26 validate regexes, 17 license enums, 13
  git_provider enums, 1 quoted `"map"`).
- `git_provider` default flip `"forgejo"` → `"github"` in the 13 cluster
  blueprints (INV-0001 OQ-2a); `"forgejo"` stays a valid value.
- Variable-surface reconciliation for go/std, go/ext, go/kubebuilder, rust/std,
  rust/esp32 using the go/k8s pinned-defaults pattern (INV-0001 OQ-3a).
- go/std: delete the dead `backstage_tags` map, add the standard Backstage
  scalars and a `license` variable (INV-0001 OQ-4a).
- Version bumps 0.1.0 → 0.2.0 for all 18 + `registry.hcl` sync (INV-0001 OQ-5a).
- Drive-by fixes riding the same PR (INV-0001 OQ-7a): go/kubebuilder hooks,
  std/docs duplicate condition, homelab/go `go_version` skew, `registry.hcl` key
  naming.
- Doc refresh where the old syntax is documented as convention: root
  `CLAUDE.md`, `docs/examples/README.md`.
- Pass 2 (Phases 6–8, second PR): `git_provider` + derived scalars → one
  `object({...})` variable across all 19 blueprints and the shared `_defaults/`
  templates (issue #14).

### Out of Scope

- New `object`/`list`/`map` variables beyond pass 2's `git_provider` object —
  pass 1 restores the registry with `string`/`bool` only.
- Re-enabling forgejo as a default or adding a gitlab provider — gitlab waits
  for real `.gitlab/` templates.
- Refreshing the `.claude/skills/` plugin content (still references
  `blueprint.yaml`) — pre-existing staleness, separate follow-up.
- Template body (`.tmpl`) changes — only `blueprint.hcl`, registry metadata, and
  docs change; emitted scaffolds must stay byte-identical for already-working
  blueprints (modulo the github default flip).

## Verified Forge Behavior

Empirical results from INV-0001 (forge 0.8.0 @ `806263d`, scratch registry) that
this plan builds on:

- `validate = "regex"` and `type = "choice"`/`choices` are **load errors**;
  quoted `type = "string"` still loads (silent compat); quoted `type = "map"` is
  a load error (typeexpr).
- Ternary cross-variable defaults (`"${git_provider == "forgejo" ? "x" : "y"}"`)
  and bare variable refs in `condition.when` work unchanged under v0.8 — only
  the `variable` block internals change.
- The fully migrated go/cli pattern scaffolds end to end: 40 files, `.forgejo/`
  excluded under `git_provider=github`, validation rejects bad enum values with
  file/line positions.
- Blueprints missing variables referenced by inherited `_defaults/` templates
  fail at **render** time (`Unknown variable`), not load time — the go/k8s fix
  (pinned scalars + `defaults { exclude }`) is the proven remedy.
- Render errors surface **one variable at a time**, so the surface gap is found
  iteratively. The authoritative check is grepping single-`$` `${var}`
  references in inherited `.tmpl` files: `$${...}` is an escape for downstream
  tools, and non-`.tmpl` files (e.g. `scripts/labels.sh`, whose
  `${color}`/`${repo_name}` are shell locals) are copied verbatim and never
  parsed. Phase 2 found `go_version` this way — it was missing from the INV-0001
  inventory table.
- Hooks are decoded but never executed (forge#41) — hook edits here are
  forward-looking, not testable.

## Implementation Phases

Each phase builds on the previous one. A phase is complete when all its tasks
are checked off and its success criteria are met. Phases 1–5 (pass 1) land as
one registry-wide PR (INV-0001 OQ-6b); Phases 6–8 (pass 2) land as a second PR
after pass 1 merges.

---

### Phase 1: Cluster-family syntax migration (13 blueprints)

Mechanical conversion of the blueprints that already declare their full variable
surface: go/cli, go/docker, std/new (byte-identical bodies), bun/std, std/docs,
homelab/{k8s,tf-modules,tf-live,images,charts, infra,docs} (byte-identical
bodies), homelab/go. The exact conversion was proven on go/cli in INV-0001
Observation 4.

#### Tasks

- [x] Migrate go/cli: bareword types, `validation` blocks for the two kebab-case
      regexes, `contains()` validation replacing the `license` and
      `git_provider` enums, `git_provider` default `"github"`; ternary defaults
      and `condition` blocks untouched; delete the trailing commented-out
      `backstage_tags` block
- [x] Propagate the migrated body to go/docker and std/new (preserve each file's
      `name`/`description`/`tags` header)
- [x] Migrate bun/std (same shape; `bun_version`/`node_version` in place of
      `go_version`)
- [x] Migrate std/docs; merge its two `git_provider != "github"` conditions into
      one exclude list; drop the commented-out hooks blocks (hooks don't execute
      — forge#41)
- [x] Migrate the 7 identical homelab bodies + homelab/go (superset with
      `go_version` and the two-command hook)
- [x] Flip `git_provider` default to `"github"` in all 13

#### Success Criteria

- All 13 load and scaffold: `forge create <bp> --set ...` succeeds with default
  provider and renders GitHub-derived values
  (`github>donaldgifford/renovate-config`, `github.com` host)
- `--set git_provider=forgejo` still renders the `.forgejo/` tree and
  fartlab-derived values (render-only check)
- `--set git_provider=gitlab` and `--set license=WTFPL` fail with `contains()`
  validation errors
- No `.tmpl` file changed; scaffold diffs vs. pre-migration output show only the
  provider-default flip

  Verified by byte-diff. A true pre-migration scaffold is impossible (main's
  blueprints don't load on forge 0.8 — that's the bug), so the baseline is
  main's blueprints with **only** the mechanical syntax swap applied: old
  `forgejo` default kept, std/docs' two conditions left unmerged. Scaffolding
  baseline and migrated with the same explicit `--set git_provider=...`
  neutralizes the default flip, isolating any other behavior change:

  | Blueprint   | `git_provider=github` | `git_provider=forgejo` |
  | ----------- | --------------------- | ---------------------- |
  | go/cli      | identical             | identical              |
  | std/docs    | identical             | identical              |
  | bun/std     | identical             | identical              |
  | homelab/k8s | identical             | identical              |

  (`.forge-lock.hcl` excluded — it records the registry path and commit.) The
  std/docs rows are the load-bearing ones: they prove merging its two duplicate
  `git_provider != "github"` condition blocks into one exclude list changed no
  output on either path.

---

### Phase 2: Surface reconciliation — go/ext, go/kubebuilder, rust/std, rust/esp32

The four license-only blueprints inherit root/category `_defaults/` templates
that reference variables they never declare (INV-0001 Observation 5). Apply the
go/k8s pinned-defaults pattern: GitHub-pinned scalars, no `git_provider` prompt,
`.forgejo/` excluded from inherited defaults.

#### Tasks

- [x] Syntax swap in all four (validate → validation, license enum →
      `contains()`, bareword types)
- [x] rust/std + rust/esp32: add `project_owner` (required, kebab-case
      validation) — inherited `justfile.tmpl` and `CONTRIBUTING.md.tmpl`
      reference it
- [x] All four: add pinned scalars — `project_org` (default
      `"${project_owner}"`), `git_host` (default `"github.com"`),
      `renovate_config_prefix` (default `"github"`)
- [x] All four: add the four Backstage `project_component_*` variables as
      `required = true` (OQ-2b — go/k8s parity, explicit Backstage identity)
- [x] All four: `defaults { exclude }` of the root `.forgejo/` relpaths — copy
      the exact-relpath list from `go/k8s/blueprint.hcl` (no globs)
- [x] go/ext + go/kubebuilder: declare `go_version` (default `"1.26.4"`) — gap
      not caught by the INV-0001 inventory; `go/_defaults/CLAUDE.md.tmpl`,
      `mise.toml.tmpl` and `go.mod.tmpl` all reference it
- [x] go/kubebuilder: add `hooks { post_create = ["git init", "go mod tidy"] }`
      (drive-by; it inherits `go/_defaults/go.mod.tmpl` so tidy is applicable)

#### Success Criteria

- INV-0001's original repro now passes: `forge create go/ext` scaffolds clean
  with only project vars supplied
- All four render the inherited surface correctly: renovate.json5,
  catalog-info.yaml, CONTRIBUTING.md, README.md
- No `.forgejo/` files in any of the four scaffold outputs
- Interactive prompt surface is exactly the project vars plus the four required
  component vars (OQ-2b); no provider prompts

  Verified with `forge info <bp>/blueprint.hcl -o json` (prompting can't be
  driven from a non-TTY — forge errors on the first required variable instead).
  All five reconciled blueprints report the same surface: seven required
  variables (`project_name`, `project_owner`, `project_description` + the four
  `project_component_*`), with `license`, `go_version` and the three provider
  scalars defaulted, and **no `git_provider` variable declared**.

---

### Phase 3: go/std rebuild

The map outlier (INV-0001 OQ-4a): drop the dead variable, align go/std with the
registry's scalar conventions, and give it the same pinned surface as Phase 2.

#### Tasks

- [x] Syntax swap on `project_name` / `project_owner` / `project_description`
- [x] Delete `backstage_tags` (`type = "map"`, required, zero template
      consumers)
- [x] Add `license` (string, `contains()` validation, default `"Apache-2.0"`) —
      inherited `README.md.tmpl` renders `${license}`
- [x] Add the four `project_component_*` variables (`required = true`, same
      shape as Phase 2)
- [x] Add pinned provider scalars + `.forgejo/` defaults-exclude (same shape as
      Phase 2)

#### Success Criteria

- go/std scaffolds end to end for the first time on forge ≥ v0.7
- Every go/std variable is scalar — nothing in the registry requires
  `--var-file` to scaffold
- Rendered catalog-info.yaml carries the component values; README renders the
  license name

---

### Phase 4: Registry metadata, drive-bys, and docs

Version bumps, `registry.hcl` hygiene, and updating the two places that document
the old syntax as the convention.

#### Tasks

- [x] homelab/go: `go_version` `"1.24"` → `"1.26.4"` (family default)
- [x] Bump `version` 0.1.0 → 0.2.0 in all 18 migrated `blueprint.hcl` files
      (go/k8s stays 0.2.0)
- [x] registry.hcl: rename the dash-keyed entries (`blueprint "go-std"`,
      `blueprint "go-kubebuilder"`) to slash form matching the rest
- [x] Run `forge registry update --registry-dir .` — expect **zero** `missing`
      warnings; verify every entry shows 0.2.0
- [x] Root `CLAUDE.md`: update the Key Conventions variable example from
      `type = "string"` to v0.8 syntax (bareword + `validation`)
- [x] `docs/examples/README.md`: replace the "Until that migration lands…"
      paragraph — the registry is now fully v0.8; note that enum values are
      enforced by `validation` blocks
- [x] Add `docs/examples/go-cli.forge-vars.hcl` showing the migrated cluster
      surface (provider + enum + Backstage vars)

#### Success Criteria

- `forge registry update` output is warning-free and `git diff registry.hcl`
  shows only intended version/key/commit changes
- `yamllint`, `markdownlint-cli2`, and `prettier --check` pass on everything
  touched
- No doc in the repo shows the removed v0.6 forms as current convention

  Audited by grepping `docs/` and root markdown for `type = "choice"`,
  `choices =` and `validate = "`. Most hits describe the removal (IMPL-0002,
  DESIGN-0004, CLAUDE.md) and are correct as written. Two **Draft** design docs
  — DESIGN-0002 and DESIGN-0003 — showed legacy `blueprint.hcl` snippets as the
  shape to build, which would have led an implementer to write syntax that no
  longer loads. Both now carry a syntax note pointing at IMPL-0003 and
  CLAUDE.md; their design intent is untouched, since rewriting proposals is out
  of scope for this migration.

---

### Phase 5: Full-registry verification and landing

Prove every blueprint scaffolds, then ship the single PR.

#### Tasks

- [x] Write `scripts/scaffold-smoke.sh` (OQ-3a) and smoke-scaffold all 19
      blueprints with minimal `--set` vars into a tmpdir: assert exit 0 and
      non-empty output for each
- [x] Negative matrix: bad `license`, `git_provider`, and `container_registry`
      values each fail with a validation error
- [x] Variant spot-checks: one cluster blueprint with `git_provider=forgejo`;
      go/k8s ghcr + ecr scaffolds unchanged (regression guard for the shared
      `_defaults/`)
- [x] Repo linters clean (yamllint / markdownlint-cli2 / prettier)
- [x] Commit (drive-bys called out in the message), push, open the single
      registry-wide PR referencing INV-0001 + this doc, with issue #14 linked as
      pass 2 (Phases 6–8)
- [x] After merge: check off pass 1 here and start Phase 6 — #19 merged as
      `9ddae0a` on 2026-08-19

#### Success Criteria

- 19/19 blueprints scaffold successfully on forge 0.8.0
- `forge registry update` reports zero `missing` warnings — the headline
  INV-0001 failure is gone
- PR is open with a green check run (if CI exists on the repo) and documents the
  drive-bys

---

### Phase 6: Pass-2 semantics validation (scratch)

Pass 2 replaces the provider scalar cluster with issue #14's `object({...})`
variable. Object semantics that pass 1 never needed — default evaluation,
prompting, partial `--set` supply — decide the final shape, so pin them down
empirically first (INV-0001-style scratch registry) before touching real files.

#### Tasks

- [x] Scratch-test object semantics on forge 0.8: does a fully-defaulted object
      skip prompting; can an object `default` carry cross-variable/ternary
      expressions; does `--set` of a partial object literal merge or replace;
      how do field-level validation failures read
- [x] Freeze the object shape (issue #14 proposal:
      `name`/`org`/`host`/`renovate_config_prefix`) with GitHub default values
      (INV-0001 OQ-2a carries over)
- [x] Grep-inventory every `${project_org}` / `${git_host}` /
      `${renovate_config_prefix}` reference across all `_defaults/` levels and
      blueprint-owned templates (INV-0001 Observation 5 is the seed list)
- [x] Draft the forgejo supply story: a `.forge-vars.hcl` overlay carrying the
      full object (fartlab values), validated in the scratch registry —
      **blocked by forge#42**, see findings
- [x] Record confirmed semantics + final shape on issue #14
      ([comment](https://github.com/donaldgifford/forge-registry/issues/14#issuecomment-5332115111))

#### Findings

Scratch registry at `/tmp/p6-reg` (copy of this branch), forge 0.8.0
(`806263d`). **The shape is validated; the supply channel is blocked.**

Working as designed:

- A fully-defaulted object needs no prompt and no supply.
- Templates traverse it natively — the 9 shared `_defaults` templates rewritten
  to `${git_provider.org}` / `.host` / `.renovate_config_prefix` render
  correctly (`module github.com/donaldgifford/objtest`).
- `condition { when = git_provider.name != "github" }` works.
- Field-level validation reads well:
  `git_provider.name must be one of: forgejo, github.` with position.
- `--set` with a **full** object literal works (forgejo variant, 34 files).

Blocked — **forge#42**: the same object supplied via `--var-file` fails with
`converting variables to cty: variable "git_provider": object required, but have string`.
Root cause is `ctyToGo` in forge's `internal/prompt/prompt.go` returning
`val.GoString()` (the Go debug representation) for non-primitive types — a stale
"vars files are scalar-only" assumption from IMPL-0008 that IMPL-0009
invalidated. The var-file loader itself is correct: it type-checks the object
and rejects partials with a good message. **Fix open as forge#43** — see
Dependencies.

Constraint — **objects replace, never merge**. All attributes are required on
every supply, and `optional(string)` / `optional(string, "default")` modifiers
are rejected
(`Optional attribute modifier is only for type constraints, not for exact types`).
So today's `--set git_provider=forgejo` — which re-derives org/host/prefix
through the ternaries — has no post-migration equivalent; switching providers
means restating all four fields.

Scope is larger than the `_defaults`-only estimate: **169 references across ~40
template files** (`project_org` 103/32, `git_host` 38/27,
`renovate_config_prefix` 28/6), including blueprint-owned templates like
`homelab/*/CLAUDE.md.tmpl`, `homelab/docs/docusaurus.config.js.tmpl`,
`homelab/go/.goreleaser.yml.tmpl`, `go/k8s/renovate.json5.tmpl` and
`std/_defaults/cliff.toml.tmpl`.

#### Success Criteria

- [x] Object default/prompt/`--set` behavior is confirmed empirically, not
      assumed
- [x] Final object shape and the complete template-reference inventory are
      posted to issue #14
- [x] The forgejo overlay renders correctly — met in Phase 7 rather than in the
      scratch registry: `docs/examples/forgejo.forge-vars.hcl` composes onto any
      base example and renders the `.forgejo/` tree with fartlab-derived values.
      Requires forge v0.8.1 (forge#43); on 0.8.0 this fails with
      `object required, but have string`.

---

### Phase 7: Pass-2 object migration (all 19 blueprints + shared templates)

#### Tasks

- [x] Replace the scalar cluster (`git_provider` enum + three ternary scalars)
      with the object variable in the 13 cluster blueprints
- [x] Convert the six pinned-scalar blueprints (go/k8s + the five reconciled in
      pass 1) to the same object with a full GitHub default (their prompt
      surface must not change)
- [x] Rewrite template references to attribute access (`${git_provider.org}`,
      `${git_provider.host}`, `${git_provider.renovate_config_prefix}`) across
      every `_defaults/` level and blueprint template from the Phase 6 inventory
- [x] Conditions: `git_provider != "github"` → `git_provider.name != "github"`
- [x] Update `docs/examples/` var-files to object literals (the README already
      previews the shape) and add the forgejo overlay
- [x] Bump migrated blueprints 0.2.0 → 0.3.0; `forge registry update`

#### Findings

Done on branch `feat/v08-object-consolidation`, verified against a build of
**forge#43** (the fix for the Phase 6 blocker). Stock forge 0.8.0 still cannot
read the object from a var-file, so this work cannot land before that fix is
released — see Dependencies.

Scope came in at **170 references across 39 template files**, marginally above
the Phase 6 estimate of 169/40. No `$${...}` escapes and no bare directive
references existed for any of the three scalars, so the rewrite was unambiguous.

Behavior preservation is proven by byte-diff, not asserted:

- **github path** — all 19 blueprints produce output byte-identical to their
  pass-1 scaffold (`.forge-lock.hcl` excluded, since it records the registry
  path).
- **forgejo path** — all 13 cluster blueprints are byte-identical to their
  pass-1 `--set git_provider=forgejo` scaffold when the object is supplied in
  full.

Two behaviors were deliberately preserved rather than tidied:

- The cluster blueprints default `git_provider.org` to the literal
  `"donaldgifford"`, while the six pinned ones default it to `project_owner` —
  exactly what the scalars they replace did. Unifying them would change emitted
  output and belongs in its own change.
- `go/k8s/go.mod.tmpl` interpolates `project_owner`, not the provider org, so a
  forgejo-targeted go/k8s emits `git.fartlab.dev/<project_owner>/...`. This
  predates the migration; the byte-diff confirms it is unchanged.

#### Success Criteria

- [x] All 19 blueprints scaffold on the object default; the forgejo overlay
      var-file renders the `.forgejo/` tree and fartlab-derived values (40 → 34
      files for go/cli, `module git.fartlab.dev/homelab/release-tool`)
- [x] No template in the repo references the removed scalar names
- [x] `--set` / var-file supply of a bad `git_provider.name` fails with the
      `contains()` validation error, on both channels, with position

---

### Phase 8: Pass-2 verification and landing

#### Tasks

- [x] Update `scripts/scaffold-smoke.sh` for object supply and run it green
      19/19
- [x] Negative matrix: bad `git_provider.name` via `--set` object literal and
      via var-file
- [x] Repo linters clean (yamllint / markdownlint-cli2 / prettier)
- [x] Commit, push, open the pass-2 PR referencing this doc, wired to close
      issue #14 on merge — PR #20, now ready for review; forge v0.8.1 shipped
      the fix it was gated on
- [ ] After merge: mark this doc Completed

#### Success Criteria

- [x] 19/19 scaffolds green with zero `forge registry update` warnings — the
      harness now runs 36 checks (19 default + 13 object-supply + 4 negative)
      and exits 0; `forge registry update` reports all blueprints up to date
- [x] Pass-2 PR is open and linked to close issue #14 — PR #20, all four checks
      green, mergeable, and no longer blocked: forge v0.8.1 ships the fix
- [ ] Every checkbox in this doc is ticked

---

## File Changes

| File                                                                                                    | Action | Description                                |
| ------------------------------------------------------------------------------------------------------- | ------ | ------------------------------------------ |
| `{go/{std,ext,cli,docker,kubebuilder},rust/{std,esp32},bun/std,std/{new,docs},homelab/*}/blueprint.hcl` | Modify | v0.8 syntax, surface fixes, 0.2.0          |
| `registry.hcl`                                                                                          | Modify | 0.2.0 entries, slash keys, commit pins     |
| `CLAUDE.md`                                                                                             | Modify | v0.8 variable syntax in Key Conventions    |
| `docs/examples/README.md`                                                                               | Modify | post-migration wording                     |
| `docs/examples/go-cli.forge-vars.hcl`                                                                   | Create | cluster-surface var-file example           |
| `scripts/scaffold-smoke.sh`                                                                             | Create | smoke harness (OQ-3a); updated in pass 2   |
| `_defaults/**` templates referencing provider scalars                                                   | Modify | pass 2: `${git_provider.*}` attribute refs |
| `docs/examples/*.forge-vars.hcl`                                                                        | Modify | pass 2: object literals + forgejo overlay  |

## Testing Plan

This repo has no build/test step — verification is scaffold-based (Phase 5,
reused in Phase 8): a positive smoke matrix over all 19 blueprints via
`scripts/scaffold-smoke.sh`, a negative validation matrix over every enum,
provider/registry variant renders, and byte-diff regression checks against
pre-migration scaffolds for blueprints that worked before.

## Open Questions

Answer format: pick a letter per question (a = recommendation), or write in your
own ("other").

**Decided 2026-08-18:** 1a, 2b, 3a, 4b.

### 1. Branch base for the migration PR

PR #17 (`fix/go-k8s`) is still open and carries INV-0001 plus the go/k8s 0.2.0
bump this plan assumes.

- **a (Recommended):** Branch off `main` after PR #17 merges. The migration PR
  starts from a registry that already contains INV-0001 and go/k8s 0.2.0; no
  stacked-PR bookkeeping.
- b: Branch off `fix/go-k8s` now and open a stacked PR — starts sooner, but
  rebases if #17 gets review changes.
- c: Add the migration commits to PR #17 itself — one PR total, but it mixes the
  go/k8s release-train review with an 18-blueprint diff.

**Decision:** a — branch off `main` once PR #17 merges.

### 2. Backstage component variables in the 5 reconciled blueprints

go/k8s declares the four `project_component_*` vars as `required` (four
interactive prompts). The five minimal blueprints need the variables to render
inherited catalog-info templates, but they've never prompted for them.

- **a (Recommended):** Add them with defaults, not `required` — zero new
  prompts, catalog-info renders sensible values:
  `project_component_type = "service"`,
  `project_component_system = "${project_name}"`,
  `project_component_lifecycle = "experimental"`,
  `project_component_owner = "${project_owner}"`. Override via `--set` or
  var-file when it matters.
- b: `required = true` like go/k8s — explicit Backstage identity every time, at
  the cost of four prompts on blueprints that are otherwise two-question
  scaffolds.
- c: Skip the variables and `defaults { exclude }` catalog-info instead —
  smallest surface, but these scaffolds lose their Backstage entity entirely.

**Decision:** b — `required = true`, go/k8s parity; explicit Backstage identity
is worth the prompts.

### 3. Smoke-verification harness

Phase 5 needs to scaffold all 19 blueprints repeatably; nothing in the repo
automates that today.

- **a (Recommended):** Commit `scripts/scaffold-smoke.sh` — iterates the
  registry, supplies minimal vars per blueprint, scaffolds into a tmpdir, prints
  a pass/fail summary. Reusable for pass 2 and any future blueprint PR; CI
  wiring can come later.
- b: Ad-hoc `forge create` commands during this PR only, documented in the PR
  description — no new repo surface, but pass 2 re-derives it.
- c: The script **plus** a GitHub Actions workflow running it on PRs (installs
  forge via `go install`) — catches regressions permanently, but adds CI that
  depends on forge releases to a repo that currently has no workflows.

**Decision:** a — commit `scripts/scaffold-smoke.sh`; CI wiring can come later.

### 4. Pass-2 (#14 object consolidation) planning

- **a (Recommended):** Write a separate IMPL doc for pass 2 after this PR merges
  — this doc stays single-purpose and pass 2 can react to anything learned
  landing pass 1.
- b: Extend this doc with pass-2 phases now — one doc for the whole v0.8 story,
  but its checkboxes span two PRs and the object shape may shift under review.
- c: Fold pass 2 into this same PR — contradicts INV-0001 decision 1a; listed
  only for completeness.

**Decision:** b — pass-2 phases added above (Phases 6–8); still a separate PR
after pass 1 merges.

## Dependencies

- PR #17 merged (OQ-1a) — carries INV-0001 and go/k8s 0.2.0; the pass-1 branch
  starts from `main` after that.
- forge 0.8.0 (`806263d`) installed locally; neither pass needs forge changes.
- forge#41 (hooks never executed) — hook edits in Phases 1–2 are forward-looking
  only.
- Phases 6–8 start only after the pass-1 PR merges; issue #14 stays open as the
  pass-2 tracker until Phase 8 closes it. (Phase 6 is scratch-only research and
  ran ahead of the merge without touching the registry.)
- **Phase 7 is gated on forge#42** — var-files cannot supply object variables in
  forge 0.8.0. Migrating before that fix ships would leave a shell-quoted
  `--set` literal as the only way to switch providers, and would make the
  `docs/examples/*.forge-vars.hcl` files unable to express the provider at all.
  See Phase 6 Findings.

  The fix is **written, tested, and open as forge#43**. A build of that branch
  resolves an object var-file correctly — attributes drive both templates
  (`module git.fartlab.dev/homelab/objtest`) and conditions (`.forgejo/`
  shipped, `.github/` excluded), field-level `validation` still fires through
  the var-file path — and scaffolds all 19 current blueprints with no
  regression. Three regression tests fail on forge `main` and pass on the
  branch.

  forge#43 also fixes a second arm of the same root cause, found while writing
  those tests: `goToCty` stringified an already-resolved `cty.Value` when
  building the `hcl.EvalContext`, so a later variable's default could not
  traverse into an object attribute (`${git_provider.host}/${git_provider.org}`)
  — on the `--set` object path as well as the var-file path. Phase 7's Task 3
  depends on that working, since several `_defaults` templates compose provider
  attributes into other variables' defaults.

  **Both gates cleared on 2026-08-19.** Pass 1 merged as `9ddae0a`, and forge#43
  merged as `d207c77` and shipped in **forge v0.8.1**. `mise.toml` now pins
  `github:donaldgifford/forge = "0.8.1"`, which is the registry's new floor: the
  object surface loads on 0.8.0, but supplying `git_provider` through a var-file
  does not work there, so 0.8.0 cannot switch providers.

  Re-verified against the released 0.8.1 binary (not a local build): the smoke
  harness is 36/36 green, including `bad git_provider.name via --var-file`,
  which is precisely the check that fails on 0.8.0. The forgejo overlay renders
  end to end — `module git.fartlab.dev/homelab/release-tool` with the
  `.forgejo/` tree, against `github.com/donaldgifford/release-tool` and
  `.github/` for the base file. `forge registry update` reports all blueprints
  up to date.

## References

- [INV-0001](../investigation/0001-migrate-remaining-blueprints-to-forge-v08-variable-syntax-and.md)
  — findings, experiments, and the seven recorded decisions
- forge `docs/MIGRATION.md` — "Variable type system upgrade (v0.7+)"
- forge-registry issue #14 — pass 2 (`git_provider` object)
- forge#41 — RunPostCreate hooks never invoked
- forge#42 — var-files cannot supply object/list/map variables (blocked Phase 7;
  filed from Phase 6 findings); fixed by forge#43, shipped in forge v0.8.1
- `go/k8s/blueprint.hcl` — reference v0.8 blueprint (pinned-defaults +
  `defaults { exclude }` pattern)
- DESIGN-0004 / IMPL-0002 — where the go/k8s pattern was established
