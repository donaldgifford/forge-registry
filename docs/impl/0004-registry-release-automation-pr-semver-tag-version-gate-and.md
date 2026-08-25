---
id: IMPL-0004
title:
  "Registry release automation: pr-semver-tag, version gate, and single-commit
  release"
status: Draft
author: Donald Gifford
created: 2026-08-23
---

<!-- markdownlint-disable-file MD024 MD025 MD041 -->

# IMPL-0004: Registry release automation: pr-semver-tag, version gate, and single-commit release

<!--toc:start-->

- [Objective](#objective)
- [Scope](#scope)
  - [In Scope](#in-scope)
  - [Out of Scope](#out-of-scope)
- [Verified Behavior (from INV-0002)](#verified-behavior-from-inv-0002)
- [Implementation Phases](#implementation-phases)
  - [Phase 1: the pr-semver-tag composite action](#phase-1-the-pr-semver-tag-composite-action)
    - [Tasks](#tasks)
    - [Success Criteria](#success-criteria)
  - [Phase 2: PR gates in ci.yml](#phase-2-pr-gates-in-ciyml)
    - [Tasks](#tasks-1)
    - [Success Criteria](#success-criteria-1)
  - [Phase 3: release.yml rewrite and workflow retirements](#phase-3-releaseyml-rewrite-and-workflow-retirements)
    - [Tasks](#tasks-2)
    - [Success Criteria](#success-criteria-2)
  - [Phase 4: docs, end-to-end verification, and upstream issue](#phase-4-docs-end-to-end-verification-and-upstream-issue)
    - [Tasks](#tasks-3)
    - [Success Criteria](#success-criteria-3)
- [File Changes](#file-changes)
- [Testing Plan](#testing-plan)
- [Dependencies](#dependencies)
- [References](#references)

<!--toc:end-->

## Objective

Implement the release design decided in INV-0002 (Addendum 1 + Addendum 2):

- **On PRs:** block blueprint changes that don't bump the blueprint's `version`,
  block blueprint changes on `dont-release` PRs, and lint PR titles as
  conventional commits (the squash subject **is** the changelog input).
- **On merge to `main`:** a single label-aware release job — compute the next
  version from the merged PR's labels, run `forge registry update`, regenerate
  `CHANGELOG.md` with `git-cliff --tag`, land both in one `chore(release)`
  commit, and tag **that** commit. `dont-release` merges do nothing.

The label→version→tag machinery is a scratch-built in-repo composite action,
`pr-semver-tag`, replacing `jefflinse/pr-semver-bump` (INV-0002 Observation 8 /
Addendum 2). Existing labels (`major` / `minor` / `patch` / `dont-release`) are
kept.

**Implements:** INV-0002 (all five Decided open questions + Addendum 2)

## Scope

### In Scope

- `.github/actions/pr-semver-tag/` — composite action (`action.yml` +
  `entrypoint.sh`), shellcheck-clean, bats-tested
- `scripts/check-blueprint-bump.sh` — the version-bump gate
- `ci.yml` — two new jobs: `version-gate`, `title-lint`
- `release.yml` — full rewrite around the two-phase flow
- `cliff.toml` — Blueprint Changes group; broadened `chore(release)` skip
- Retirement of `changelog.yml` and `changelog-regen.yml`
- `_defaults/` policy: a `_defaults/` change requires bumping every blueprint it
  feeds (category `_defaults/` → that category; root `_defaults/` → all)
- Docs: CLAUDE.md + contributor-facing workflow docs
- Filing the upstream forge issues: content-hash pin (INV-0002 OQ-4) and
  remote-fetch defaults (INV-0002 Addendum 3)

### Out of Scope

- Promoting the action to a standalone `donaldgifford/pr-semver-tag` repo
  (deliberately deferred until it has survived a few real releases)
- GitHub Release objects (`gh release create`) — tags only, matching current
  behavior; can be added to the release job later
- The forge content-hash pin itself (upstream issue only)
- Handling blueprint _deletion_ (registry entry removal is manual today; the
  gate warns and skips dirs whose `blueprint.hcl` is gone)
- Prerelease/build-metadata semver segments — bare `vX.Y.Z` only

## Verified Behavior (from INV-0002)

Facts the design leans on, each verified empirically during INV-0002:

- `GITHUB_SHA` stays pinned to the squash-merge commit for the entire workflow
  run, so PR lookup by commit works even after the job pushes new commits.
- `git tag` with no commit argument tags the workspace `HEAD` — the property
  that lets the release commit be tagged (Observation 10, action-bumpr crib).
- `git-cliff --tag vX.Y.Z` names the unreleased section as `vX.Y.Z` before the
  tag exists (Observation 9).
- `registry.hcl` and `CHANGELOG.md` sit outside every `<bpPath>/` pin filter, so
  the release commit does not re-stale the pins it writes (Observations 2 and
  4).
- Pushes made with the default `GITHUB_TOKEN` do not trigger new workflow runs,
  so the release commit cannot re-trigger `release.yml`; the `chore(release)`
  guard is belt-and-braces. (Consequence: a tag-triggered workflow would also
  not fire — another reason the release job does its own tagging inline.)
- The registry has 19 blueprints across 5 categories: `bun`, `go`, `homelab`,
  `rust`, `std` — the scope alternation used by the gate and `cliff.toml`.

## Implementation Phases

Each phase builds on the previous one. A phase is complete when all its tasks
are checked off and its success criteria are met.

---

### Phase 1: the `pr-semver-tag` composite action

`.github/actions/pr-semver-tag/` — one `action.yml`, one `entrypoint.sh` (~100
lines), architecture cribbed from `action-bumpr` (MIT, audited in INV-0002
Observation 10).

**Interface.** Inputs: `mode` (`compute` | `tag`, required), `github-token`
(default `${{ github.token }}`), `major-label` / `minor-label` / `patch-label`
(defaults `major` / `minor` / `patch`), `noop-labels` (default `dont-release`),
`tag-prefix` (default `v`), `target` (default `HEAD`). Outputs: `skip`,
`bump-level`, `current-version`, `next-version`, `pr-number`. Composite actions
don't auto-populate `INPUT_*`, so `action.yml` passes each input via `env:`
explicitly (as action-bumpr does).

**Behavior.** Both modes are stateless and share the same computation:

1. Find the merged PR:
   `gh api "repos/$GITHUB_REPOSITORY/commits/$GITHUB_SHA/pulls"` (first
   element). No PR found (direct push) → `skip=true`, warn, exit 0.
2. Map labels → bump level, precedence major > minor > patch. A noop label, or
   no semver label at all, → `skip=true`, exit 0 (`pr-labels.yml` already
   guarantees exactly one label, so this is defense in depth).
3. Current version:
   `git tag --merged HEAD -l "${PREFIX}[0-9]*" | sort -V | tail -1`; no tags →
   `0.0.0` base. Merged-only filtering means tags on unmerged branches can't
   leak in — stricter than pr-semver-bump's repo-wide default, and no API
   pagination to get wrong (Observation 11).
4. Next version: split on `.`, increment per level — pure bash.
5. `mode: compute` stops here, emitting outputs. `mode: tag` creates an
   annotated tag `vX.Y.Z` on `target` with message `vX.Y.Z: PR #N - <title>`,
   fails loudly if the tag exists, pushes it (checkout's persisted credentials;
   caller needs `contents: write`), and comments the released version on the PR
   (`gh pr comment`).

#### Tasks

- [ ] Write `action.yml`: inputs/outputs above, `runs.using: composite`,
      explicit `env:` plumbing for every input
- [ ] Write `entrypoint.sh` with `set -Eeuo pipefail`, functions for each step
      (`find_pr`, `bump_level_from_labels`, `current_version`, `next_version`,
      `create_tag`), and a `[[ "${BASH_SOURCE[0]}" == "$0" ]]` main guard so
      bats can source it
- [ ] Handle the edge cases: no PR for `GITHUB_SHA`, no semver label, zero
      existing tags, tag already exists, multiple labels (precedence)
- [ ] `shellcheck` clean; follow Google style per repo shell conventions
- [ ] Write bats tests for the pure functions: label mapping (all four labels +
      none + multiple), version parsing/increment (from `0.0.0`, from `v0.1.4`,
      each level), tag-name assembly with prefix
- [ ] Add `bats` to `mise.toml` dev tools so the tests run locally and in CI

#### Success Criteria

- `bats .github/actions/pr-semver-tag/test/` passes
- `shellcheck entrypoint.sh` reports nothing
- A `workflow_dispatch` smoke run of `mode: compute` on `main` emits
  `current-version` matching `git describe --tags --abbrev=0` and `skip=true`
  (no PR associated with a dispatch)

---

### Phase 2: PR gates in ci.yml

Two new jobs alongside the existing labeler. Both run on `pull_request` only.

**`version-gate`** runs `scripts/check-blueprint-bump.sh` (checkout with
`fetch-depth: 0`). The script:

1. Computes changed files:
   `git diff --name-only origin/$GITHUB_BASE_REF...HEAD`.
2. Classifies each changed path:
   - `<cat>/<name>/**` where `<cat>/<name>/blueprint.hcl` exists on the branch →
     that blueprint must bump.
   - `<cat>/_defaults/**` → every blueprint in `<cat>` must bump.
   - `_defaults/**` (root) → every blueprint must bump.
   - Changed dir whose `blueprint.hcl` is gone (deletion) → warn and skip.
   - Everything else (docs, workflows, `registry.hcl`, scripts) → ignored.
3. For each blueprint that must bump, asserts
   `git diff origin/$GITHUB_BASE_REF...HEAD -- <bp>/blueprint.hcl` contains a
   `+version` line. Reports every violation (not just the first) with the
   `::error::` annotation format, then exits non-zero.
4. If any blueprint must bump **and** the PR carries `dont-release` (labels read
   from the event payload, passed in as an env var), fails with a message
   explaining that blueprint changes require a real semver label.

Blueprint discovery is `git ls-files -- '*/*/blueprint.hcl'` — a brand-new
blueprint added in the same PR is found on the branch, and its wholesale-new
`blueprint.hcl` naturally contains a `+version` line, so scaffolding a new
blueprint passes without special-casing.

**`title-lint`** runs `amannn/action-semantic-pull-request` (SHA-pinned, on
`opened` / `edited` / `synchronize` / `reopened`): standard types, scope
optional, but when a scope is present it must match
`^([a-z0-9-]+|(bun|go|homelab|rust|std)/[a-z0-9-]+)$` so blueprint scopes are
well-formed for the `cliff.toml` group.

#### Tasks

- [ ] Write `scripts/check-blueprint-bump.sh` per the spec above
      (`set -Eeuo pipefail`, plain globals — no `local -n`, bash 3.2 safe for
      local runs)
- [ ] `shellcheck` clean
- [ ] Bats tests for the classification + assertion logic against fixture git
      repos in `$BATS_TMPDIR` (blueprint change with/without bump, category
      `_defaults/` fan-out, root `_defaults/` fan-out, deletion skip, docs-only
      no-op, dont-release rejection)
- [ ] Add the `version-gate` job to `ci.yml` (checkout `fetch-depth: 0`, labels
      passed via `${{ toJSON(github.event.pull_request.labels.*.name) }}`)
- [ ] Add the `title-lint` job to `ci.yml` with the scope regex and
      `pull_request` types above
- [ ] Add a `action-tests` job (or fold into `version-gate`) running the bats
      suites from Phases 1–2 in CI

#### Success Criteria

- Fixture-driven bats suite passes locally and in CI
- A draft PR editing `go/cli/mise.toml.tmpl` without a bump fails `version-gate`
  with a `::error::` naming `go/cli`; adding the bump turns it green (verified
  on a scratch PR before merging this phase)
- A PR titled `Chore/reg bump` fails `title-lint`; `chore(go/cli): probe` passes
- Docs-only PRs (like the one landing this doc) pass both gates untouched

---

### Phase 3: release.yml rewrite and workflow retirements

**`cliff.toml`** (do first — the release job consumes it):

- Add, **ahead of** the generic type parsers:

  ```toml
  { message = "^[a-z]+\\((bun|go|homelab|rust|std)/[a-z0-9-]+\\)", group = "Blueprint Changes" },
  ```

- Broaden `^chore\(release\): prepare for` to `^chore\(release\)` so release
  commits stay out of the next release's section (the existing
  `^chore.*[Cc]hangelog` skip is unchanged and still covers historical auto-sync
  commits).

**`release.yml`** rewrite:

```yaml
on: { push: { branches: [main] } }
permissions: { contents: write, pull-requests: write }
jobs:
  release:
    if: ${{ !startsWith(github.event.head_commit.message, 'chore(release)') }}
    steps:
      - harden-runner (audit), checkout (fetch-depth: 0), mise-action
      - id: ver — uses: ./.github/actions/pr-semver-tag  (mode: compute)
      - if skip != 'true':
          forge registry update --registry-dir .
          git-cliff --tag ${next-version} -o CHANGELOG.md
          commit "chore(release): ${next-version}"   # registry.hcl + CHANGELOG.md
          push origin HEAD:main
      - if skip != 'true':
          uses: ./.github/actions/pr-semver-tag      (mode: tag)
```

The commit step commits only if something changed (a merge that alters neither
pins nor changelog still tags — the tag then lands on the merge commit itself,
which is correct). A push race against a concurrent merge to `main` fails the
job; re-running it is safe because every step is idempotent-or-guarded (regen
converges, `mode: tag` fails loudly on an existing tag).

**Retirements:** delete `changelog.yml` and `changelog-regen.yml`. If branch
protection lists the drift check as required, drop it there too.

#### Tasks

- [ ] `cliff.toml`: add the Blueprint Changes parser ahead of the generic rules;
      broaden the `chore(release)` skip
- [ ] Verify locally that `git-cliff` output is unchanged for existing history
      except grouping (no entries gained/lost)
- [ ] Rewrite `release.yml` per the sketch (harden-runner + SHA-pinned actions,
      matching `changelog-regen.yml` conventions)
- [ ] Delete `.github/workflows/changelog.yml` and
      `.github/workflows/changelog-regen.yml`
- [ ] Check branch protection / required checks for references to the retired
      workflows and update
- [ ] `yamllint` clean on all touched workflow files

#### Success Criteria

- `git-cliff -o /dev/null` runs warning-free on the new config (legacy
  non-conventional commits still skipped, count unchanged)
- The first non-`dont-release` merge after this phase produces: exactly one
  `chore(release): vX.Y.Z` commit on `main` containing `registry.hcl` +
  `CHANGELOG.md`, an annotated tag on that commit, and a bot comment on the
  merged PR
- A `dont-release` merge produces no commit, no tag, no comment

---

### Phase 4: docs, end-to-end verification, and upstream issue

#### Tasks

- [ ] Update `CLAUDE.md`: authors no longer run `forge registry update` (the
      release job owns `registry.hcl`); blueprint edits require a `version` bump
      (gate-enforced); PR titles are conventional commits with optional
      `<category>/<name>` scope
- [ ] Update `docs/` contributor docs (registry workflow page) with the new PR →
      release lifecycle and a diagram of the single-commit flow
- [ ] Update the `/blueprint-bump-version` and `/registry-validate` skill docs
      if they reference the retired manual-sync workflow
- [ ] End-to-end verification, release path: merge a real blueprint PR with a
      `patch` label; confirm the tag points at the release commit
      (`git rev-parse vX.Y.Z^{commit}`), `forge registry update --check` exits 0
      at that tag, and the changelog section renders the entry under Blueprint
      Changes
- [ ] End-to-end verification, noop path: merge a `dont-release` docs PR;
      confirm no tag, no release commit, `--check` unchanged from before the
      merge
- [ ] File the upstream forge issue: squash/rebase merges orphan the
      `latest_commit` pin (INV-0002 Observation 5); propose a content-hash or
      hybrid pin; link INV-0002
- [ ] File the second forge issue (INV-0002 Addendum 3): remote fetch with no
      ref dies on `git checkout ""` (pre-created dst forces go-getter's update
      path); propose `owner/repo` defaulting to github.com behind `--git-host` /
      `--git-host-type` flags (defaults `github.com` / `github`, so today's
      commands don't change), normalization to the git getter form, and default
      ref = latest `v*` tag with default-branch fallback
- [ ] Mark INV-0002 references to IMPL-0004 as landed; set this doc's status to
      Completed

#### Success Criteria

- Both end-to-end paths verified on `main` with real merges
- `forge registry update --check` exits 0 on `main` immediately after a release
  — the drift class that triggered INV-0002 is gone
- Upstream issue filed and linked in References

---

## File Changes

| File                                          | Action | Description                                    |
| --------------------------------------------- | ------ | ---------------------------------------------- |
| `.github/actions/pr-semver-tag/action.yml`    | Create | Composite action interface                     |
| `.github/actions/pr-semver-tag/entrypoint.sh` | Create | Compute/tag implementation                     |
| `.github/actions/pr-semver-tag/test/*.bats`   | Create | Unit tests for pure functions                  |
| `scripts/check-blueprint-bump.sh`             | Create | Version-bump gate                              |
| `scripts/test/check-blueprint-bump.bats`      | Create | Fixture-repo tests for the gate                |
| `.github/workflows/ci.yml`                    | Modify | Add `version-gate`, `title-lint`, bats jobs    |
| `.github/workflows/release.yml`               | Modify | Full rewrite: two-phase single-commit release  |
| `.github/workflows/changelog.yml`             | Delete | Drift check retired                            |
| `.github/workflows/changelog-regen.yml`       | Delete | Folded into the release job                    |
| `cliff.toml`                                  | Modify | Blueprint Changes group; `chore(release)` skip |
| `mise.toml`                                   | Modify | Add `bats` dev tool                            |
| `CLAUDE.md` / `docs/`                         | Modify | New contributor workflow                       |

## Testing Plan

- [ ] Bats: pure-function coverage for the action (labels, semver math, tag
      assembly) — no network, no git required
- [ ] Bats: fixture git repos for the gate script (six scenarios listed in
      Phase 2)
- [ ] `shellcheck` + `yamllint` on everything touched, as CI already runs
- [ ] Scratch-PR verification for gate behavior before the gates become blocking
      (Phase 2 success criteria)
- [ ] Real-merge verification for both release paths (Phase 4)

## Dependencies

- forge ≥ 0.8.1 and git-cliff via `mise.toml` (already pinned);
  `jdx/mise-action` in workflows
- `gh` and `jq` — preinstalled on `ubuntu-latest` runners
- `bats` — added to `mise.toml` in Phase 1
- No new marketplace dependencies beyond the SHA-pinned
  `amannn/action-semantic-pull-request`

## References

- [INV-0002](../investigation/0002-ci-enforcement-of-blueprint-version-bumps-and-registry-sync.md)
  — the investigation this implements (Observations 1–11, Addendums 1–2)
- [haya14busa/action-bumpr](https://github.com/haya14busa/action-bumpr) —
  architectural crib (MIT): HEAD-tagging, `merge_commit_sha` PR lookup
- [jefflinse/pr-semver-bump](https://github.com/jefflinse/pr-semver-bump) — the
  action being replaced (MIT)
- [amannn/action-semantic-pull-request](https://github.com/amannn/action-semantic-pull-request)
  — PR title lint
- `.github/workflows/changelog-regen.yml` — the harden-runner + SHA-pin +
  bot-push conventions the new `release.yml` follows (before retirement)
- IMPL-0003 — where the squash-induced pin drift was hit (PRs #19, #20, #21)
