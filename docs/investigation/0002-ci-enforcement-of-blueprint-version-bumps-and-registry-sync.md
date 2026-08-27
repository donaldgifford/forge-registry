---
id: INV-0002
title: "CI enforcement of blueprint version bumps and registry sync"
status: Concluded
author: Donald Gifford
created: 2026-08-19
---

<!-- markdownlint-disable-file MD024 MD025 MD041 -->

# INV-0002: CI enforcement of blueprint version bumps and registry sync

<!--toc:start-->

- [Question](#question)
- [Hypothesis](#hypothesis)
- [Context](#context)
- [Approach](#approach)
- [Environment](#environment)
- [Findings](#findings)
  - [Observation 1: --check already exists and is exactly the CI primitive](#observation-1---check-already-exists-and-is-exactly-the-ci-primitive)
  - [Observation 2: staleness is a git-log comparison, not a content hash](#observation-2-staleness-is-a-git-log-comparison-not-a-content-hash)
  - [Observation 3: --check does not enforce version bumps](#observation-3---check-does-not-enforce-version-bumps)
  - [Observation 4: the second PR is not required — a second commit is](#observation-4-the-second-pr-is-not-required--a-second-commit-is)
  - [Observation 5: squash and rebase merges both invalidate the pin](#observation-5-squash-and-rebase-merges-both-invalidate-the-pin)
  - [Observation 6: the repo already has the auto-sync pattern](#observation-6-the-repo-already-has-the-auto-sync-pattern)
- [Conclusion](#conclusion)
- [Recommendation](#recommendation)
- [Open Questions](#open-questions)
  - [1. How to close the version-bump gap](#1-how-to-close-the-version-bump-gap)
  - [2. How to handle post-merge pin drift](#2-how-to-handle-post-merge-pin-drift)
  - [3. Where the registry check should live](#3-where-the-registry-check-should-live)
  - [4. Whether to pursue an upstream forge change](#4-whether-to-pursue-an-upstream-forge-change)
  - [5. Scope of the first implementation](#5-scope-of-the-first-implementation)
- [Addendum: release-flow design (2026-08-20)](#addendum-release-flow-design-2026-08-20)
  - [Observation 7: squash commit subjects broke the changelog](#observation-7-squash-commit-subjects-broke-the-changelog)
  - [Observation 8: pr-semver-bump cannot tag a commit created mid-run](#observation-8-pr-semver-bump-cannot-tag-a-commit-created-mid-run)
  - [Observation 9: git-cliff --tag dissolves the ordering cycle](#observation-9-git-cliff---tag-dissolves-the-ordering-cycle)
  - [Observation 10: an existing action fits — haya14busa/action-bumpr](#observation-10-an-existing-action-fits--haya14busaaction-bumpr)
  - [The release flow](#the-release-flow)
  - [Consequences for existing workflows](#consequences-for-existing-workflows)
- [Addendum 2: fork vs. scratch (2026-08-23)](#addendum-2-fork-vs-scratch-2026-08-23)
  - [Observation 11: the fork delta is small — the ownership is not](#observation-11-the-fork-delta-is-small--the-ownership-is-not)
  - [Decision: scratch-build pr-semver-tag as a composite action](#decision-scratch-build-pr-semver-tag-as-a-composite-action)
- [Addendum 3: remote-fetch defaults (2026-08-25)](#addendum-3-remote-fetch-defaults-2026-08-25)
  - [Observation 12: remote fetch without a ref is broken](#observation-12-remote-fetch-without-a-ref-is-broken)
  - [Observation 13: bare URLs route to the http getter](#observation-13-bare-urls-route-to-the-http-getter)
  - [Decision: default ref = latest v* tag; normalize URLs](#decision-default-ref--latest-v-tag-normalize-urls)
- [References](#references)

<!--toc:end-->

## Question

Can `forge` block a PR in GitHub Actions when someone edits a blueprint but does
not bump its `version` and does not run `forge registry update` — and can the
current two-step workflow (merge the blueprint, then open a second PR to sync
`registry.hcl`) be eliminated?

## Hypothesis

That `registry.hcl`'s `latest_commit` is inherently self-referential — an entry
cannot record the hash of the commit that contains it — so a CI check would
always be one commit behind, and a follow-up PR would be structurally
unavoidable.

**This turned out to be wrong**, and the real cause is somewhere else entirely.

## Context

Every blueprint entry in `registry.hcl` carries a `latest_commit` pin. Twice
during IMPL-0003 the pins went stale immediately after merge, each time
requiring a follow-up commit that did nothing but re-run
`forge registry update`. The assumption was that this is inherent to the design.

The repo also has no protection against the more basic mistake: editing a
template and forgetting to bump the blueprint's `version`, which silently ships
changed output under an unchanged version number.

**Triggered by:** IMPL-0003 (pins went stale after both the #19 and #20 merges)

## Approach

All experiments were run against the real registry on a scratch branch, with
every scratch commit reset afterwards. `git` merge strategies were simulated
locally rather than by opening throwaway PRs.

1. Read `forge registry update`'s implementation at the pinned **v0.8.1** tag to
   establish how staleness is computed.
2. Probe `--check` against an uncommitted edit, then the same edit committed.
3. Test whether the "commit blueprint, sync, commit `registry.hcl`" sequence
   converges on a branch.
4. Simulate squash merge, rebase merge, and true merge commit; run `--check`
   after each.
5. Test whether `--check` fires when a template changes but `version` does not.

## Environment

| Component        | Version / Value                                         |
| ---------------- | ------------------------------------------------------- |
| forge            | 0.8.1 (`d207c77`), pinned in `mise.toml`                |
| registry         | `main` @ `fb39168`, all 19 blueprints at 0.3.0          |
| Source of truth  | `internal/registrycmd/update.go` at tag `v0.8.1`        |
| Merge strategies | squash, merge, and rebase all currently enabled on repo |

## Findings

### Observation 1: `--check` already exists and is exactly the CI primitive

No forge change is needed for the registry half of this. `forge registry update`
ships a `--check` flag whose help text names CI explicitly:

```console
$ forge registry update --help
Use --check for CI mode: reports stale entries and exits non-zero without
modifying any files.
```

Verified: exit `0` on a clean tree, exit `1` with a `files-changed` warning when
stale. It writes nothing.

### Observation 2: staleness is a git-log comparison, not a content hash

From `update.go` at v0.8.1:

```go
func latestCommitForPath(registryDir, bpPath string) (string, error) {
	args := []string{"-C", registryDir, "log", "-1", "--format=%H", "--", bpPath + "/"}
	...
}
```

Each entry is compared on two axes — `version` and `latest_commit` — producing
four statuses: `up-to-date`, `version-changed`, `files-changed`, `both-changed`.

Two consequences follow from this being a **git-log** comparison:

- **Only committed changes are visible.** An uncommitted edit to
  `go/cli/mise.toml.tmpl` still reports `up-to-date`. Harmless for CI, which
  always operates on commits, but it means `--check` is useless as a pre-commit
  hook.
- **The path filter is `<bpPath>/`.** `registry.hcl` lives at the repo root, so
  committing a registry sync does **not** re-bump any blueprint's pin. This is
  the detail that makes Observation 4 work.

### Observation 3: `--check` does not enforce version bumps

This is the gap. `forge registry update` copies `blueprint.hcl`'s version into
`registry.hcl`; it never asserts that the version _changed_. So the following
sequence passes cleanly with the version untouched:

```console
$ echo "# probe" >> go/cli/mise.toml.tmpl && git commit -am "template change, NO version bump"
$ forge registry update --check
warning:   go/cli    files-changed          # ← fires here

$ forge registry update && git commit -am "sync registry"
$ forge registry update --check
✓ All blueprints up to date                 # ← exit 0
$ grep '^version' go/cli/blueprint.hcl
version     = "0.3.0"                       # ← never bumped
```

`--check` answers _"is `registry.hcl` consistent with the tree?"_, not _"did the
author bump the version they were supposed to?"_. **The two halves of the
original request need two different mechanisms.**

### Observation 4: the second PR is not required — a second commit is

The premise behind the follow-up-PR workflow does not hold. Because the pin's
path filter excludes `registry.hcl` (Observation 2), the sync converges **within
a single branch**:

```console
$ git commit -m "bump go/cli to 0.4.0"        # blueprint change
$ forge registry update --check
warning:   go/cli    both-changed                exit=1

$ forge registry update && git commit -m "sync registry"   # registry-only commit
$ forge registry update --check
✓ All blueprints up to date                       exit=0
```

Two commits in one PR, no second PR. This is already what a `--check` CI job
would demand, and it is satisfiable.

### Observation 5: squash and rebase merges both invalidate the pin

Here is the actual cause of the recurring drift. Simulating each strategy
against a converged branch:

| Merge strategy   | `--check` on main after merge | Why                                |
| ---------------- | ----------------------------- | ---------------------------------- |
| **Squash**       | exit **1**, `files-changed`   | collapses N commits into a new SHA |
| **Rebase**       | exit **1**, `files-changed`   | replays commits under new SHAs     |
| **Merge commit** | exit **0**, `up-to-date`      | original SHAs preserved verbatim   |

After a simulated squash merge the pin does not merely lag — it points at a
commit that is **not in `main`'s history at all**:

```console
$ git merge-base --is-ancestor "$PIN" HEAD
NO — pin references a commit absent from main's history
```

Rebase-merge failing is the non-obvious one: it produces linear history and
preserves commit _messages_, but rewrites every SHA, so the pin is just as dead
as under squash. Only a true merge commit keeps the referenced objects
reachable.

The repo currently allows all three strategies, and recent PRs (#19, #20, #21)
were squash-merged — which is precisely why the pins broke each time.

### Observation 6: the repo already has the auto-sync pattern

`.github/workflows/changelog-regen.yml` solves the identical shape of problem
for `CHANGELOG.md`: on push to `main` it regenerates the artifact, commits it,
and guards against self-triggering:

```yaml
if: ${{ !startsWith(github.event.head_commit.message, 'chore(changelog)') }}
```

paired with a `changelog.yml` PR job that fails on drift. A registry equivalent
would be a near-copy, and would make post-merge pin drift self-healing
regardless of merge strategy.

## Conclusion

**Answer: Yes — and more cheaply than expected.**
`forge registry update --check` is a drop-in CI gate today and needs no forge
changes. The hypothesis that a follow-up PR is structurally unavoidable is
**refuted**: a registry-sync commit on the same branch converges, because the
pin's path filter ignores `registry.hcl`.

The recurring drift is **caused by squash-merging**, not by forge. Squash and
rebase both rewrite SHAs and orphan the pin; a merge commit does not.

Two caveats shape the implementation:

- `--check` does **not** enforce version bumps (Observation 3). That half needs
  a separate check comparing changed paths against `blueprint.hcl` version
  diffs.
- `--check` only sees committed changes, so it belongs in CI, not a pre-commit
  hook.

## Recommendation

> **2026-08-20:** Partially superseded by the
> [Addendum](#addendum-release-flow-design-2026-08-20). The PR-time `--check`
> job is dropped and the regen moves into a label-aware release job; item 1's
> version-bump script and the self-healing principle of item 2 survive.

Pair a PR-time gate with post-merge self-healing, mirroring the changelog setup
the repo already runs:

1. **`registry.yml` PR job** — `forge registry update --check`, failing the PR
   when `registry.hcl` is out of sync. Add a second step that diffs changed
   `<category>/<name>/**` paths against `blueprint.hcl` version changes to close
   the Observation 3 gap.
2. **`registry-regen.yml` push-to-main job** — re-run `forge registry update`
   and auto-commit, with a `chore(registry)` loop guard. This absorbs
   squash-induced drift permanently and makes the merge-strategy question moot.

Answers to the open questions below should drive an IMPL doc.

## Open Questions

Answer format: pick a letter per question (a = recommendation), or write in your
own ("other").

### 1. How to close the version-bump gap

> **Decided (2026-08-20): a** — the diff script, running as a job in `ci.yml`.
> Extended with one more rule: blueprint changes on a `dont-release` PR are
> rejected outright (see [Consequences](#consequences-for-existing-workflows)).

`--check` cannot detect an unbumped version (Observation 3). Something has to
compare "which blueprint directories did this PR touch?" against "which
`blueprint.hcl` versions changed?".

- **a (Recommended):** A shell step in the PR workflow. For each
  `<category>/<name>/` with changes in
  `git diff --name-only origin/main...HEAD`, assert
  `git diff origin/main...HEAD -- <bp>/blueprint.hcl` contains a `+version`
  line. ~15 lines of bash, no new dependencies, and it reuses the `scripts/`
  conventions already in the repo.
- b: Require a `blueprint-change` PR label and check it, leaving the judgement
  to the author — simpler, but trivially forgotten and unenforced.
- c: Ask forge for a `--require-bump` flag on `registry update --check` so the
  whole thing is one command — cleanest long-term, but blocks this work on an
  upstream release.
- d: Skip it. Treat registry sync as the only gate and rely on review to catch
  unbumped versions.

### 2. How to handle post-merge pin drift

> **Decided (2026-08-20): a, amended** — the regen is folded into the release
> job as part of a single release commit rather than a standalone
> `registry-regen.yml`, and it is label-aware: `dont-release` merges do not
> regen or tag. See [The release flow](#the-release-flow).

Squash merge orphans the pin every time (Observation 5).

- **a (Recommended):** Add `registry-regen.yml` — auto-sync on push to `main`
  with a `chore(registry)` loop guard, copying `changelog-regen.yml`. Keeps
  squash merging, self-heals, zero author burden.
- b: Disable squash and rebase merges on the repo, requiring merge commits for
  everything. No new automation, but it changes the merge policy for every PR in
  the repo to serve one file, and produces a noisier history.
- c: Keep squash but require merge commits **only** for PRs touching blueprints
  — narrower than (b), but it is a convention no CI can easily enforce.
- d: Accept the drift and let the next PR's auto-sync fix it, treating pins as
  eventually-consistent.

### 3. Where the registry check should live

> **Decided (2026-08-20): b** — the version-bump gate runs as a job in the
> existing `ci.yml`. The PR-time `--check` job is dropped entirely: the release
> job owns `registry.hcl`, and authors never run `forge registry update` again
> (a `--check` on PRs would fail for every author following the new workflow).
> No `registry.yml` is created.

- **a (Recommended):** A new `registry.yml` workflow, matching the existing
  one-concern-per-file layout (`changelog.yml`, `pr-labels.yml`,
  `trufflehog.yml`).
- b: A job inside the existing `ci.yml`, which today only runs the labeler —
  fewer files, but `ci.yml` becomes a grab bag.
- c: Extend `scripts/scaffold-smoke.sh` to also assert registry freshness, so
  one script covers all verification — but it conflates scaffold correctness
  with metadata hygiene.

### 4. Whether to pursue an upstream forge change

> **Decided (2026-08-20): a** — file the upstream issue describing the
> squash/rebase failure mode; nothing here blocks on it.

The pin is a commit SHA, which is what makes it fragile under history rewrites.
A content hash of the blueprint directory would be immune to squash, rebase, and
cherry-pick alike.

- **a (Recommended):** File an issue describing the squash/rebase failure mode
  and propose a content-hash (or hybrid) pin, but do not block this work on it.
  The CI plan above stands on its own and stays valid either way.
- b: Implement the content-hash change in forge first, then wire up CI — fixes
  the root cause, but it is a breaking registry-format change requiring a
  migration for every existing entry.
- c: Leave forge alone; the auto-sync workflow makes the fragility invisible in
  practice.

### 5. Scope of the first implementation

> **Decided (2026-08-20): a** — moot in the amended design: the gate and the
> regen ship together because the regen is not a separate workflow any more. One
> PR delivers the `ci.yml` jobs, the rewritten `release.yml`, the label rename,
> and the `cliff.toml` changes.

- **a (Recommended):** Ship the PR check and the auto-sync workflow together.
  They are complementary — the check without auto-sync means a red `main` after
  every squash merge, which trains people to ignore it.
- b: PR check first, observe how often drift actually bites, add auto-sync only
  if warranted.
- c: Auto-sync first (it removes existing pain immediately), add the PR gate
  once the noise is gone.

## Addendum: release-flow design (2026-08-20)

Follow-up research after review set the direction: the version-bump gate runs as
a `ci.yml` job, changelog entries carry the blueprint as their scope, and the
regen is label-aware so that `dont-release` merges produce neither a tag nor a
regen — letting the repo's version tags serve as the registry's version. The
remaining question was whether replacing `pr-semver-bump` required custom code
(~20 lines of bash, or a reusable custom action). It does not: an existing
action fits (Observation 10). Each open question above carries its **Decided**
line; the evidence is below.

### Observation 7: squash commit subjects broke the changelog

The changelog's raw material is the squash commit subject, which GitHub takes
from the **PR title** — branch commits are destroyed. Two releases have already
fallen victim:

```console
$ git log --format=%s v0.1.2..v0.1.4 | grep -v changelog
Chore/reg bump (#26)
Fix/std rm go (#25)
```

Neither parses as a conventional commit, so git-cliff skips both, the release
sections render empty and are dropped — v0.1.3 and v0.1.4 are absent from
`CHANGELOG.md` entirely.

Consequence: any commit-message convention, including a blueprint scope, is
enforceable only as a **PR title lint**. `amannn/action-semantic-pull-request`
(1.4k stars, active) does exactly this as a `ci.yml` job. With titles like
`feat(go/std): add lint target`, a `cliff.toml` parser placed ahead of the
generic rules routes blueprint changes to their own group:

```toml
{ message = "^[a-z]+\\((go|rust)/[a-z0-9-]+\\)", group = "Blueprint Changes" },
```

rendering as `*(go/std)* Add lint target` under **Blueprint Changes**.

### Observation 8: pr-semver-bump cannot tag a commit created mid-run

The release design requires tagging a commit the workflow itself creates (the
release commit carrying `registry.hcl` + `CHANGELOG.md`).
`jefflinse/pr-semver-bump` hardcodes the tag target to the _triggering_ commit —
`version.js`'s `createRelease()` passes `object: process.env.GITHUB_SHA` — so it
can only ever tag the squash-merge commit. No input overrides it. The action has
to be replaced, not reconfigured.

### Observation 9: `git-cliff --tag` dissolves the ordering cycle

The apparent circularity — the changelog needs the tag name, but the tag should
point at the commit containing the changelog — is solved by `--tag`, which
generates the changelog _as if_ the tag existed:

```console
$ git-cliff --tag v0.2.0 -o CHANGELOG.md    # tag does not exist yet
## [0.2.0] - 2026-08-20                     # ← named section, no [unreleased]
```

Verified on this repo. Compute the next version, generate the changelog, commit,
then tag that commit. No second git-cliff run, and `main` and the tag point at
identical trees.

### Observation 10: an existing action fits — haya14busa/action-bumpr

> **2026-08-23:** Verdict superseded by
> [Addendum 2](#addendum-2-fork-vs-scratch-2026-08-23). The survey stands, but
> the adoption call flipped: rather than pay `action-bumpr`'s label-rename cost
> and own an external dependency, the same ~100 lines are built in-repo.
> `action-bumpr` remains the architectural reference (MIT).

Survey of semver-bump actions against the two required properties: bump level
read from **PR labels**, and the ability to tag a **commit created during the
same run**:

| Action                             | Label-driven     | Tags mid-run commit    | Verdict            |
| ---------------------------------- | ---------------- | ---------------------- | ------------------ |
| `jefflinse/pr-semver-bump`         | yes              | no — `GITHUB_SHA` only | replace            |
| `haya14busa/action-bumpr`          | yes              | **yes — tags `HEAD`**  | **use**            |
| `mathieudutour/github-tag-action`  | no (commit msgs) | yes (`commit_sha`)     | wrong driver       |
| `rymndhng/release-on-push-action`  | yes              | no                     | no                 |
| `K-Phoen/semver-release-action`    | yes              | no                     | no, stale          |
| `zwaldowski/semver-release-action` | yes              | —                      | archived           |
| `actions-ecosystem/*`              | yes (composable) | —                      | node12, stale      |
| `intuit/auto`                      | yes              | yes                    | replaces git-cliff |

`action-bumpr` (composite shell action, auditable, active 2025) has exactly the
right mechanics, verified in its `entrypoint.sh`:

- On push to `main` it finds the merged PR via `merge_commit_sha == GITHUB_SHA`,
  reads its labels, and computes the next version from the latest reachable tag.
  `GITHUB_SHA` stays pinned to the squash commit for the whole run, so the
  lookup still works after the workflow pushes new commits.
- It tags with a bare `git tag -a "${NEXT_VERSION}"` — **the workspace `HEAD`**,
  not `GITHUB_SHA`. Create the release commit first and the tag lands on it.
  This is the property no other label-driven action has.
- `dry_run: true` emits `next_version` / `skip` outputs without tagging — the
  first phase of the two-phase flow, and the value `git-cliff --tag` needs.
- A merged PR with no `bump:*` label yields `skip=true` and exits cleanly —
  `dont-release` semantics for free.
- It comments the released version back on the merged PR.

The one cost: bump labels are **hardcoded** as `bump:major` / `bump:minor` /
`bump:patch`. Adopting it means renaming the three semver labels (a one-time
`gh label rename` plus `pr-labels.yml` and docs updates); `dont-release` can
stay, functioning as "no bump label attached". Given the alternative is writing
and maintaining bespoke code, the rename is cheap — no custom action needs to
exist.

### The release flow

> **2026-08-23:** Shape unchanged; steps 1 and 6 are now the in-repo
> `pr-semver-tag` action (`mode: compute` / `mode: tag`) instead of
> `action-bumpr` — see [Addendum 2](#addendum-2-fork-vs-scratch-2026-08-23).

One workflow (`release.yml`, rewritten), one release commit, one tag:

```text
squash-merge to main
  │  guard: head commit is not chore(release)
  ▼
1. action-bumpr (dry_run) ─► skip? ─► stop          [dont-release]
  │           └─ next_version = vX.Y.Z
2. forge registry update                    # heal squash-orphaned pins
3. git-cliff --tag vX.Y.Z -o CHANGELOG.md
4. commit "chore(release): vX.Y.Z"          # registry.hcl + CHANGELOG.md
5. push main
6. action-bumpr (real) ─► tags HEAD = release commit, comments on PR
```

Properties:

- The tagged commit contains its own changelog section and the corrected pins —
  a consumer resolving the tag gets correct SHAs, which is what lets repo tags
  act as the registry's version.
- Pin-safe by Observations 2 and 4: `registry.hcl` and `CHANGELOG.md` are
  repo-root files outside every `<bpPath>/` filter, so the release commit does
  not re-stale the pins it just wrote.
- `dont-release` merges leave no tag and no regen. Their commits appear in the
  _next_ release's changelog section, which is where Keep a Changelog wants them
  anyway.
- The release-commit push cannot re-trigger the workflow at all — pushes made
  with the default `GITHUB_TOKEN` never start new runs. The `chore(release)`
  guard is belt-and-braces on top of that.

### Consequences for existing workflows

> **2026-08-23:** The `pr-labels.yml` bullet below is void — the scratch-built
> action keeps `major` / `minor` / `patch` / `dont-release` as-is
> ([Addendum 2](#addendum-2-fork-vs-scratch-2026-08-23)). Everything else
> stands.

- `release.yml` — rewritten as above; `pr-semver-bump` retired.
- `changelog.yml` (PR drift check) — **retired**. The changelog regenerates at
  release, so PRs no longer carry changelog commits at all. This also removes
  the recurring failure where `main` moving underneath a branch fails the drift
  check.
- `changelog-regen.yml` — **retired**, folded into the release job.
- `ci.yml` — gains two jobs: the version-bump gate script and the PR title lint
  (Observation 7).
- Authors stop running `forge registry update` entirely; the release job owns
  `registry.hcl`, and no `--check` runs on PRs.
- `pr-labels.yml` — required-label set becomes `bump:major` / `bump:minor` /
  `bump:patch` / `dont-release`.
- `cliff.toml` — add the blueprint-scope group (Observation 7), and broaden the
  skip rule `^chore\(release\): prepare for` to `^chore\(release\)` so release
  commits stay out of the next release's section.
- The gate also **rejects blueprint changes on `dont-release` PRs** — otherwise
  a blueprint edit would merge with no regen and no tag, leaving `blueprint.hcl`
  ahead of `registry.hcl` until the next release.

One known gap is carried forward, not solved here: edits under `_defaults/`
change scaffold output for every blueprint in the category but live outside each
`<bpPath>/` filter — the pins never notice, and the gate as scoped above would
not demand a bump. Whether a `_defaults/` change should force a bump of every
blueprint in its category is an IMPL-doc decision (the batch
`/blueprint-bump-version` skill makes it cheap either way).

## Addendum 2: fork vs. scratch (2026-08-23)

Review direction after Addendum 1: adopting `action-bumpr` means paying its
label-rename cost and owning an external dependency anyway — "we also take on
those costs ourselves, and that's why we build it ourselves." The remaining
question: fork `jefflinse/pr-semver-bump` and add the two missing inputs, or
build the same functionality from scratch?

### Observation 11: the fork delta is small — the ownership is not

What a fork would actually change (both repos are MIT-licensed):

- Labels are already configurable (`major-label` / `minor-label` / `patch-label`
  / `noop-labels`) — no rename under a fork either.
- Two new inputs close the gap: `dry-run` (skip `createRelease()`) and
  `commit-sha` (override `object: process.env.GITHUB_SHA`). Roughly 25 lines of
  source.

What the fork owns regardless of how small the delta is:

- The JS action lifecycle: `@vercel/ncc` bundles committed to `dist/` on every
  change, npm/Dependabot churn on `@actions/*`, the jest suite, and GitHub's
  recurring forced node runtime migrations (node12 → 16 → 20 so far).
- Upstream's latent bugs. One was found just reading the source:
  `getCurrentVersion()` calls `listMatchingRefs` **without pagination**, so past
  ~100 tags the listing truncates and the computed current version can be wrong.
  A repo that tags every merge gets there.

The features that make `pr-semver-bump` ~500 lines are the ones this design does
not use: release-notes extraction from PR bodies (git-cliff's job here) and
`validate` mode (`pr-labels.yml` already enforces labels).

### Decision: scratch-build `pr-semver-tag` as a composite action

Build it as ~100 lines of shell in an in-repo composite action —
`.github/actions/pr-semver-tag/` — cribbing `action-bumpr`'s audited
architecture (MIT). Every mechanism it needs was verified during this
investigation:

| Piece           | Implementation                                              |
| --------------- | ----------------------------------------------------------- |
| Find merged PR  | `gh api repos/{repo}/commits/{GITHUB_SHA}/pulls` — one call |
| Labels → level  | case statement over inputs; **existing label names stay**   |
| Current version | `git tag --merged HEAD -l 'v*' \| sort -V \| tail -1`       |
| Next version    | split on `.`, increment — pure bash                         |
| Tag             | `git tag -a "$NEXT" [target]` — **defaults to `HEAD`**      |
| PR comment      | `gh pr comment`                                             |

Two-phase interface matching [The release flow](#the-release-flow):

```yaml
- id: ver
  uses: ./.github/actions/pr-semver-tag
  with:
    mode: compute # outputs: skip, current-version, next-version
# … forge registry update, git-cliff --tag, chore(release) commit, push …
- uses: ./.github/actions/pr-semver-tag
  with:
    mode: tag # tags HEAD by default; comments the version on the PR
```

Why scratch wins over the fork:

- No build step — matching this repo's no-build, lint-enforced philosophy — and
  shellcheck + bats testing per the conventions `scripts/scaffold-smoke.sh`
  already follows.
- `major` / `minor` / `patch` / `dont-release` survive untouched;
  `pr-labels.yml` does not change.
- Current-version computation is git-only (no API pagination to get wrong), and
  merged-only tag filtering is stricter than upstream's repo-wide default.
- It lives in-repo first (`uses: ./…` needs no pinning or publishing); promote
  to a standalone `donaldgifford/pr-semver-tag` repo once it has survived a few
  real releases — promotion is a directory copy plus a `uses:` pin change, at
  which point the forge repo can adopt it too.

Implementation is specced in IMPL-0004.

## Addendum 3: remote-fetch defaults (2026-08-25)

The first real attempt to consume a registry **remotely** (a private repo)
failed with `git exited with 128: fatal: empty string is not a valid pathspec`.
Diagnosis showed it is neither an auth problem nor private-specific — it
reproduces identically against this public registry — and it surfaced a
consumer-side QOL gap that this investigation's release design is uniquely
positioned to close.

### Observation 12: remote fetch without a ref is broken

The causal chain, each step verified against forge v0.8.1 and go-getter v2.2.3
(its latest v2):

1. forge **pre-creates** the destination directory before fetching
   (`resolveRegistrySource` uses `os.MkdirTemp`; `Cache.GetOrFetch` uses
   `MkdirAll`).
2. go-getter's `Get()` chooses clone-vs-update by `os.Stat(req.Dst)` — the
   directory exists, so it always takes the **update** path. The clone path is
   unreachable.
3. `update()` runs `git init` → `remote add` → `fetch --tags` (auth happens
   here, and succeeds) → `reset --hard FETCH_HEAD` → then `git checkout <ref>`
   **unconditionally**, with `ref=""` when the URL carries no `?ref=`.
4. Modern git (2.55 here) makes `git checkout ""` fatal:
   `fatal: empty string is not a valid pathspec`, exit 128, which go-getter
   wraps as `git exited with 128`.

The clone path would have been safe — its checkout is guarded by `ref != ""` —
and go-getter has no fixed release to bump to.

**Verified workaround:** any explicit ref. Public and private both work:

```console
$ forge create go/std \
    --registry-dir "git::https://github.com/<owner>/<registry>.git?ref=main"
```

Private repos need nothing else locally — https auth comes from `gh`'s
credential helper and SSH from the agent. (A gitconfig `insteadOf` rewrite was
suspected but turned out to be inert — `[extraConfig.url "…"]` is home-manager
syntax, not git's `[url "…"]` — and unnecessary.) CI fetching a private registry
would need a token; local use does not.

### Observation 13: bare URLs route to the http getter

The documented short form `github.com/<owner>/<repo>` (no `git::` prefix, no
`.git` suffix) is detected as an **http** source, not git. For a private repo
the web URL returns an unauthenticated 404, so the user sees
`bad response code: 404` — an auth problem wearing a not-found costume. The
`.git`-suffixed bare form tries git first (hitting Observation 12), then falls
back to http and reports both errors.

### Decision: default ref = latest v* tag; normalize URLs

An upstream forge change, recorded here because it completes this
investigation's consumer story:

- **Default host, not host guessing.** The short form gets shorter:
  `--registry-dir you/registry` assumes **github.com**. Two flags make the host
  explicit instead of inferred from URL shape:
  - `--git-host` (default `github.com`) — the host to prepend to a bare
    `owner/repo`. `gitlab.com` is a known value, tracked for completeness only;
    github is the only host that matters today.
  - `--git-host-type` (default `github`) — names the host flavor so
    host-specific behavior has somewhere to live later (forgejo, gitlab) without
    changing today's commands. With the defaults, every command that works now
    keeps working unchanged.

  Resolution order: an existing local path wins (current behavior); explicit
  `git::` / `ssh://` / `https://` forms pass through untouched; a dotted first
  segment (`git.fartlab.dev/owner/repo`) is treated as `host/owner/repo`; a bare
  `owner/repo` gets `--git-host` prepended. The normalized result is always the
  git getter form (`git::https://host/owner/repo.git`), which retires
  Observation 13's http-getter fallthrough for registries.

- **Default ref.** When no ref is given, resolve the **latest `v*` tag** (one
  `git ls-remote --tags` pre-flight, semver sort, prereleases and peeled `^{}`
  entries excluded) and fall back to the default branch
  (`git ls-remote --symref <url> HEAD`) when no tags exist. Explicit `@ref` /
  `?ref=` always override.
- **Why the tag default is right _because of this investigation_:** the release
  flow (Addendum 1) guarantees pins are correct exactly at `v*` tags — the
  tagged release commit carries the regenerated `registry.hcl` — while `main`'s
  tip can be transiently stale between a merge and the release job. Defaulting
  consumers to the latest tag means
  `forge create go/std --registry-dir you/registry` always scaffolds from a
  coherent release, and `go/std@v0.5.0` naturally means "registry release
  v0.5.0". Tags-as-registry-version stops being a convention and becomes the
  default consumption model.
- Resolving the ref before fetch also makes the cache meaningful
  (`cacheMeta.Ref` is currently `""` for default fetches) and incidentally
  guarantees the ref is never empty — though the dst-exists bug (Observation 12)
  should be fixed regardless, by pointing go-getter at a not-yet-existing
  subdirectory so the clone path runs.

Scope check: this is a contained forge change — a normalize function keyed by
two defaulted flags, an ls-remote pre-flight with a semver sort, and two
call-site fixes — filed 2026-08-26 as
[forge#44](https://github.com/donaldgifford/forge/issues/44); the content-hash
pin proposal remains a separate IMPL-0004 Phase 4 task.

## References

- [INV-0001](0001-migrate-remaining-blueprints-to-forge-v08-variable-syntax-and.md)
  — the v0.8 migration investigation
- IMPL-0003 — where the pin drift was hit twice, after #19 and after #20
- forge `internal/registrycmd/update.go` @ `v0.8.1` — `latestCommitForPath`,
  `detectStatus`
- `.github/workflows/changelog-regen.yml` / `changelog.yml` — the drift-check +
  auto-sync pattern this proposal mirrors
- forge#43 — the var-file object fix shipped in v0.8.1
- [haya14busa/action-bumpr](https://github.com/haya14busa/action-bumpr) —
  `entrypoint.sh` verified for the tag-`HEAD` and label-grep behavior
- [jefflinse/pr-semver-bump](https://github.com/jefflinse/pr-semver-bump) —
  `version.js` `createRelease()` pins the tag to `GITHUB_SHA`
- [amannn/action-semantic-pull-request](https://github.com/amannn/action-semantic-pull-request)
  — PR title lint enforcing conventional squash subjects
- v0.1.3 / v0.1.4 — the two releases missing from `CHANGELOG.md` (Observation 7)
- [go-getter v2.2.3 `get_git.go`](https://github.com/hashicorp/go-getter/blob/v2.2.3/get_git.go)
  — `Get()` clone-vs-update on `os.Stat(dst)`; `update()`'s unguarded
  `git checkout <ref>` (Observation 12)
- forge `internal/getter` / `cmd/create.go` `resolveRegistrySource` /
  `internal/registry/cache.go` @ `v0.8.1` — the pre-created destination and the
  unused `RegistryConfig.Ref` (Observation 12)
- [forge#44](https://github.com/donaldgifford/forge/issues/44) — the Addendum 3
  bug + features, filed upstream
