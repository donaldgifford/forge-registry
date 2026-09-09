---
id: INV-0003
title: "Forge go-k8s scaffold audit before initial commit"
status: Open
author: Donald Gifford
created: 2026-09-08
---

<!-- markdownlint-disable-file MD025 MD041 -->

# INV-0003: Forge go-k8s scaffold audit before initial commit

> Written inside the freshly forged `authz` repo on 2026-09-08 (where it was
> that repo's INV-0001) and copied here verbatim. "This repo" in the text below
> means `authz`, not forge-registry.

<!--toc:start-->

- [Question](#question)
- [Hypothesis](#hypothesis)
- [Context](#context)
- [Approach](#approach)
- [Environment](#environment)
- [Findings](#findings)
  - [Observation 1: Repo-location values are rendered from the project owner instead of the git provider org](#observation-1-repo-location-values-are-rendered-from-the-project-owner-instead-of-the-git-provider-org)
  - [Observation 2: Project-name fan-out is consistent but wide](#observation-2-project-name-fan-out-is-consistent-but-wide)
  - [Observation 3: Re-running forge create leaves the previous render's named directories behind](#observation-3-re-running-forge-create-leaves-the-previous-renders-named-directories-behind)
  - [Observation 4: Template escaping bug swallowed ${2} in the chart's cliff.toml](#observation-4-template-escaping-bug-swallowed-2-in-the-charts-clifftoml)
  - [Observation 5: Text leaked from the repos the blueprint files were lifted from](#observation-5-text-leaked-from-the-repos-the-blueprint-files-were-lifted-from)
  - [Observation 6: Scaffold text that is stale or contradicts the release contract](#observation-6-scaffold-text-that-is-stale-or-contradicts-the-release-contract)
  - [Observation 7: Backstage catalog values look like unedited defaults](#observation-7-backstage-catalog-values-look-like-unedited-defaults)
  - [Observation 8: Implicit invariant: the project name must equal the GitHub repo name](#observation-8-implicit-invariant-the-project-name-must-equal-the-github-repo-name)
  - [Observation 9: Lock-file and settings oddities](#observation-9-lock-file-and-settings-oddities)
  - [Observation 10: What the blueprint already gets right](#observation-10-what-the-blueprint-already-gets-right)
- [Conclusion](#conclusion)
- [Open Questions](#open-questions)
- [Recommendation](#recommendation)
  - [A. This repo, before git init](#a-this-repo-before-git-init)
  - [B. forge-registry, go/k8s blueprint and shared defaults](#b-forge-registry-gok8s-blueprint-and-shared-defaults)
  - [C. Variable model and catalog template](#c-variable-model-and-catalog-template)
- [References](#references)

<!--toc:end-->

## Question

Which files in this freshly forged repo carry values that are wrong for this
project (name, GitHub owner, URLs, leaked text from other repos), and for each
one, is the defect in the values we fed forge or in the `go/k8s` blueprint
itself?

Two audiences:

- **This repo**: a checklist to work through before `git init`, so the first
  commit is the scaffold with every reference pointing at the right place.
- **forge-registry**: the subset that is a blueprint bug (inconsistent variable
  use, hardcoded strings, template-escaping mistakes, copied text) to fix at the
  source so the next forged repo does not need this doc.

Scope: everything outside `tmpp/`. That directory holds the design docs for the
next phase and is not part of the scaffold.

## Hypothesis

Most project-name occurrences are correctly rendered from `project_name` and
will fall to a single rename. The real problems will be places where the
blueprint reaches for a different variable than its neighbours (owner vs org),
strings it should have templated but did not, and text copied from whichever
repo the blueprint file was lifted from.

## Context

The repo was generated on 2026-09-08 by forge 0.8.1 from the `go-k8s` blueprint
(`go/k8s` in `github.com/donaldgifford/forge-registry`). It has never been
committed.

Forge was run three times in place while this audit was open:

| Render | Time (UTC) | `project_name` | `project_owner` | Outcome                                                   |
| ------ | ---------- | -------------- | --------------- | --------------------------------------------------------- |
| 1      | 10:47      | `boilermate`   | `authd`         | Stale variables file. Exposed the owner-variable misuse.  |
| 2      | 12:32      | `authd`        | `donaldgifford` | Fixed owner and name; left render 1's directories behind. |
| 3      | 12:37      | `authz`        | `donaldgifford` | Final name. Stale directories removed by hand.            |

The findings record what render 1 exposed about the blueprint and what still
stands in the render 3 tree.

**Triggered by:** first-commit prep for the authz service; feeds a fix PR
against forge-registry.

## Approach

1. Enumerate the scaffold: every file outside `tmpp/`.
2. Grep for the forge variable values and classify each hit as
   rendered-from-variable, hardcoded, or external reference that should stay.
3. Grep for template residue and placeholders (`{{`, `${`, `CHANGEME`, `TODO`,
   `example.com`, `placeholder`).
4. Read every config, workflow, chart, and doc file in full and note values that
   contradict each other or the release contract in `CLAUDE.md`.
5. Cross-check the GitHub owner against reality with `gh`.
6. Sort findings into "fix here" vs "fix in the blueprint".
7. After each forge re-run, re-sweep and mark each finding resolved, still
   present, or newly introduced.

## Environment

| Component                                               | Version / Value                                                         |
| ------------------------------------------------------- | ----------------------------------------------------------------------- |
| forge                                                   | 0.8.1                                                                   |
| blueprint                                               | `go-k8s` (`go/k8s`), registry `github.com/donaldgifford/forge-registry` |
| Current render                                          | 3 (12:37Z): `project_name = authz`, `project_owner = donaldgifford`     |
| forge `git_provider.org` (all renders)                  | `donaldgifford`                                                         |
| forge `project_component_type` / `system` / `lifecycle` | `cli` / `dev-tools` / `production`                                      |
| Working directory                                       | `~/code/authz` (no `.git`)                                              |
| `gh api user`                                           | `donaldgifford`                                                         |
| `gh repo view donaldgifford/authz`                      | does not exist yet                                                      |

## Findings

### Observation 1: Repo-location values are rendered from the project owner instead of the git provider org

**Status in render 3:** latent. Both variables are `donaldgifford`, so the
rendered tree is self-consistent and nothing needs fixing here. The blueprint
defect is unchanged and will bite the next project whose `project_owner` differs
from `git_provider.org`.

The two variables are intentionally distinct. `project_owner` is the
organisational owner (the Backstage sense: the team or account that owns the
component) and `git_provider.{host,org}` is where the repo lives. Having both is
correct. The bug is which one the templates reach for: fifteen files build
`github.com/<owner>/<name>` and `ghcr.io/<owner>/...` from `project_owner`, and
those are all repo-location concerns that belong to `git_provider.org`. Only
three files use `git_provider.org`, and those three are right.

In render 1 (`project_owner = authd`, `git_provider.org = donaldgifford`) the
split looked like this.

Files rendered from `project_owner` (all should be `git_provider.org`):

| File                                       | Lines              | What it is                                                |
| ------------------------------------------ | ------------------ | --------------------------------------------------------- |
| `go.mod`                                   | 1                  | module path                                               |
| `justfile`                                 | 16, 17, 22         | `project_owner`, `go_package`, `goimports_local`          |
| `.golangci.yml`                            | 287, 294           | goimports / gci local prefix                              |
| `.goreleaser.yml`                          | 75, 76, 87, 88, 93 | `release.github.owner`, image and chart refs, compare URL |
| `cliff.toml`                               | 37, 78             | `<REPO>` postprocessor and issue link base                |
| `charts/<name>/cliff.toml`                 | 40, 80             | same, for the chart changelog                             |
| `docker-bake.hcl`                          | 13, 53             | `REGISTRY` default, `org.opencontainers.image.source`     |
| `charts/<name>/values.yaml`                | 12                 | `image.repository`                                        |
| `charts/<name>/tests/deployment_test.yaml` | 26, 34             | expected image ref                                        |
| `charts/<name>/README.md.gotmpl`           | 15                 | `helm install` OCI URL                                    |
| `helm.just`                                | 10, 86             | `helm_oci`, k3d image import ref                          |
| `README.md`                                | 62                 | chart OCI URL                                             |
| `CLAUDE.md`                                | 3                  | `<owner>/<name>`                                          |
| `.github/ISSUE_TEMPLATE/config.yml`        | 5                  | security advisory URL                                     |
| `.github/dependabot.yml`                   | 23, 39, 55         | `assignees`                                               |

Files rendered from `git_provider.org` (correct):

| File                 | Lines  | What it is                     |
| -------------------- | ------ | ------------------------------ |
| `catalog-info.yaml`  | 10     | `backstage.io/source-location` |
| `CONTRIBUTING.md`    | 17, 34 | issues URL, clone URL          |
| `.github/CODEOWNERS` | 5      | `* @<org>`                     |

References to `donaldgifford` that are **external and correct** regardless of
where a project lives: `renovate.json5` (shared config repo), `mise.toml:40-41`
(docz tool source), `security.yml:19` (`govulncheck-action`),
`.claude/settings.json` (plugin marketplace), `.forge-lock.hcl:5` (registry
URL), `catalog-info.yaml:18` (`spec.owner`, from `project_component_owner`).

The release train itself is immune: `release.yml` derives `IMAGE_REPO`,
`CHART_NAMESPACE`, and `CHART_NAME` from `github.repository` /
`github.repository_owner` / `github.event.repository.name` (lines 50-52), and
`ci.yml:102` passes `github.repository` to codecov. `scripts/labels.sh:277`
reads the repo from `gh repo view`. So when the two variables disagree, CI
publishes to `ghcr.io/<actual-owner>/<actual-repo>` while the chart's
`values.yaml` pulls from `ghcr.io/<project_owner>/<name>`, and goreleaser tries
to create the GitHub Release on the `project_owner` repo (lines 75-76).

One more thing for the registry to check: in render 1 `project_owner` did not
reach any Backstage-facing output. `catalog-info.yaml`'s `spec.owner` renders
from `project_component_owner`, so the only consumers of `project_owner` were
the fifteen wrong ones. Either `project_owner` and `project_component_owner` are
meant to be the same variable, or `project_owner` currently has no correct use
in the `go/k8s` blueprint.

`.github/dependabot.yml` `assignees` is a special case. It needs a GitHub login
with access to the repo, which a Backstage-style owner (a team name) may not be.
`git_provider.org` is the safer source, or a dedicated maintainers variable.

**Classification:** blueprint bug. Every repo URL, module path, and image ref
must render from `git_provider.host` + `git_provider.org`; `project_owner`
should only feed ownership metadata.

### Observation 2: Project-name fan-out is consistent but wide

**Status in render 3:** resolved for this repo. Every occurrence reads `authz`
and no `boilermate` or `authd` string survives outside `tmpp/` and this doc.
Recorded because it is the blast radius of a `project_name` change and the
reason Observation 3 matters.

Every occurrence traces back to `project_name`; nothing is hardcoded to a
different name. Outside the chart (17 files plus one directory):

| File                                | Lines                             |
| ----------------------------------- | --------------------------------- |
| `cmd/<name>/` (directory)           | path                              |
| `cmd/<name>/main.go`                | 1, 25                             |
| `go.mod`                            | 1                                 |
| `justfile`                          | 1, 15, 39                         |
| `helm.just`                         | 1, 8, 86                          |
| `docker.just`                       | 1                                 |
| `Dockerfile`                        | 17, 20, 22                        |
| `docker-bake.hcl`                   | 1, 13, 33, 37, 41, 53, 77, 86, 92 |
| `.goreleaser.yml`                   | 3, 13, 16, 17, 18, 76, 87, 88, 93 |
| `cliff.toml`                        | 1, 5, 37, 78                      |
| `.gitignore`                        | 8                                 |
| `.codecov.yml`                      | 10                                |
| `.github/ISSUE_TEMPLATE/config.yml` | 5                                 |
| `catalog-info.yaml`                 | 6, 7, 10                          |
| `charts/.yamllint.yml`              | 19                                |
| `README.md`                         | 1, 17, 18, 19, 32, 41, 62, 68, 69 |
| `CONTRIBUTING.md`                   | 1, 17, 34, 35                     |
| `CLAUDE.md`                         | 3, 7, 11, 15, 21, 23, 34, 75      |

Inside the chart (22 files plus the chart directory): `Chart.yaml`,
`values.yaml`, `values.schema.json`, `README.md.gotmpl`, `CHANGELOG.md`,
`cliff.toml`, `templates/_helpers.tpl` (11 named helpers), the eight template
files that `include` them, and seven unittest suites with `RELEASE-NAME-<name>`
expectations.

Two literal paths could be made name-agnostic in the blueprint:

- `.gitignore:8` ignores `/<name>`, the bare `go build` output.
- `charts/.yamllint.yml:19` ignores `charts/<name>/templates`.
  `charts/*/templates` would survive future renames.

**Classification:** repo fix (done by the re-runs). Optional blueprint tidy-up
for the two literals.

### Observation 3: Re-running forge create leaves the previous render's named directories behind

**Status in render 3:** resolved by hand. The tree now has exactly `cmd/authz/`
and `charts/authz/`, and `charts/*/` expands to one path. The forge behaviour is
unchanged.

Render 2 wrote `cmd/authd/` and `charts/authd/` but did not remove
`cmd/boilermate/` and `charts/boilermate/` from render 1. Twenty-six stale files
remained, nothing else in the tree referenced them, and they still carried
render 1's owner (`ghcr.io/authd/boilermate`).

```text
$ find cmd charts -maxdepth 1      # after render 2
cmd/authd
cmd/boilermate
charts/.yamllint.yml
charts/authd
charts/boilermate

$ echo charts/*/
charts/authd/ charts/boilermate/
```

What that breaks:

| Consumer                          | Line    | Effect                                                                                                                      |
| --------------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------- |
| `release.yml`                     | 311     | `chart_dir=$(echo charts/*/)` assumes one chart; it gets two paths in one string and every later `${CHART_DIR}` step fails. |
| `ci.yml`                          | 79, 210 | `helm lint charts/*/` and `helm unittest charts/*/` lint and test the stale chart too.                                      |
| `helm.just`                       | 27      | `ct lint --config ct.yaml --all` lints both charts.                                                                         |
| `go build ./...`, `golangci-lint` |         | Compile and lint a second `main` package.                                                                                   |
| `.github/labeler.yml`             | 9       | `cmd/**.go` matches the stale main.                                                                                         |

Root cause: `.forge-lock.hcl` only tracks category and registry defaults (see
Observation 9). Blueprint-owned paths that embed a variable,
`cmd/$${project_name}` and `charts/$${project_name}`, have no lock entry, so
forge has no record of the old path to prune when the variable changes.

**Classification:** forge / blueprint bug. Repo fix was `rm -rf` of the old
directories. Forge fix is to track variable-derived paths in the lock and prune
(or at least warn about) the old ones on re-create and sync.

### Observation 4: Template escaping bug swallowed `${2}` in the chart's cliff.toml

**Status in render 3:** still present at `charts/authz/cliff.toml:58`.
Reproduced identically in all three renders.

The root and chart cliff configs are meant to be identical apart from the header
text. The root file kept its capture groups; the chart copy lost them.

`cliff.toml:55` (correct):

```toml
{ pattern = '\((\w+\s)?#([0-9]+)\)', replace = "([#${2}](<REPO>/issues/${2}))" },
```

`charts/authz/cliff.toml:58` (broken):

```toml
{ pattern = '\((\w+\s)?#([0-9]+)\)', replace = "([#2](<REPO>/issues/2))" },
```

Every PR reference in the chart changelog would render as `#2` linking to
issue 2. The chart cliff.toml source in the blueprint needs `$${2}` (the same
escaping `.forge-lock.hcl:185` uses for `cmd/$${project_name}`), or the root
file's escaping needs copying over.

**Classification:** blueprint bug. Repo fix is to restore `${2}` on that line.

### Observation 5: Text leaked from the repos the blueprint files were lifted from

**Status in render 3:** all still present.

| File                             | Lines        | Leak                                                                                                                                                                  |
| -------------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CONTRIBUTING.md`                | 47-49, 65-68 | Branch and commit examples are docz's (`feat/plan-doc-type`, `fix/slug-truncation`, `feat(cmd): add plan document type`, `test(index): add dry-run edge case tests`). |
| `mise.toml`                      | 12-14        | Comment on mockery v3 cites "See IMPL-0021 Phase 7", an implementation doc from another repo. There is no IMPL-0021 here.                                             |
| `.github/workflows/security.yml` | 25           | Comment links to `oapi-codegen/oapi-codegen`'s code-scanning tab.                                                                                                     |

None of these break anything. They are noise a reader will trip over and they
identify the blueprint's provenance rather than this project.

**Classification:** blueprint bug (registry-default and category-default files).
Repo fix is to rewrite or delete the lines.

### Observation 6: Scaffold text that is stale or contradicts the release contract

**Status in render 3:** all still present.

| File                               | Lines | Problem                                                                                                                                                                                                                                                               |
| ---------------------------------- | ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `README.md`                        | 18-19 | Tells the reader to `mkdir -p cmd/authz` and create `main.go`, but forge already rendered `cmd/authz/main.go`. The "Getting started" block predates the `main.go.tmpl` default.                                                                                       |
| `.github/CODEOWNERS`               | 4-5   | Comment says "Replace @org/CHANGEME with your actual team" but the rendered line is already `* @donaldgifford`. Stale instruction from before the file was templated.                                                                                                 |
| `.github/PULL_REQUEST_TEMPLATE.md` | 10-11 | Says chart-only changes "still publish if Chart.yaml's version advanced". `CLAUDE.md`, `Chart.yaml:7-12`, and `release.yml:13-17` all say `Chart.yaml` is never bumped and versions are lockstep. A reader following the PR template would bump `Chart.yaml` by hand. |
| `.github/labeler.yml`              | 59-60 | `feature` label matches head branches `^feature` / `feature`. `CONTRIBUTING.md:47-52` and the git-workflow skill use `feat/` prefixes, which match neither pattern. `feat/*` PRs never get the label.                                                                 |

**Classification:** blueprint bug for all four. Repo fix is to edit the text;
the labeler pattern should become `["^feat", "feature"]` or the CONTRIBUTING
types should change, not both.

### Observation 7: Backstage catalog values look like unedited defaults

**Status in render 3:** still present; the variables file was not changed for
these.

`catalog-info.yaml` renders `spec.type: cli`, `spec.system: dev-tools`, and
`spec.lifecycle: production` from `project_component_type`,
`project_component_system`, and `project_component_lifecycle`. This is a
Kubernetes-deployed HTTP service, and a `go/k8s` blueprint should not default
`type` to `cli`. `production` is a bold default for an empty repo.

**Classification:** both. The values were accepted at forge time (repo fix: set
`type: service`, pick a real system name, consider `experimental`), and the
`go/k8s` blueprint should default `project_component_type` to `service`
(blueprint fix).

### Observation 8: Implicit invariant: the project name must equal the GitHub repo name

**Status in render 3:** satisfied, provided the GitHub repo is created as
`donaldgifford/authz`. The project, the directory, and the intended repo name
now agree.

`release.yml` sets `CHART_NAME` from `github.event.repository.name` (line 52)
and expects `helm package` to have produced `${CHART_NAME}-${version}.tgz` (line
376). `helm package` names the archive after `Chart.yaml`'s `name`, which is
`project_name`. If the repo name and `project_name` ever differ, the push step
fails on a missing file. Likewise `IMAGE_REPO` is `github.repository` (line 50)
while `values.yaml:12` hardcodes `ghcr.io/donaldgifford/authz`, so a differently
named repo would publish one image path and the chart would pull another.

**Classification:** blueprint documentation gap. The blueprint should either
assert `project_name == repo name` at forge time or document it next to the
release train description in `CLAUDE.md` / `README.md`.

### Observation 9: Lock-file and settings oddities

**Status in render 3:** unchanged.

- `.forge-lock.hcl:185-188`: the `cmd/$${project_name}/main.go.tmpl` entry is
  the only one with no `hash`. Every other default has one. A future
  `forge sync` cannot tell whether the file was modified.
- The lock tracks only category and registry defaults. Blueprint-owned files
  (`justfile`, `Dockerfile`, `docker-bake.hcl`, the chart, the CI and release
  workflows, `README.md`, `CLAUDE.md`) have no entry, so forge cannot detect
  drift in them or prune renamed paths (Observation 3).
- `.forge-lock.hcl:89-93` labels `.gitignore` as `registry-default`, yet the
  rendered file is Go-specific, comments "supplements registry-root .gitignore",
  and contains the project-specific `/authz` line. The provenance label does not
  match the content.
- `.claude/settings.json` enables both `ralph-loop@claude-plugins-official`
  (line 5) and `donald-loop@donaldgifford-claude-skills` (line 17), and
  `.gitignore:56-57` reserves `.claude/donald-loop.local.md`. It also enables
  `docker@donaldgifford-claude-skills` (line 11). Neither `donald-loop` nor
  `docker` appears in the marketplace's current skill list. These are
  category-default files and the same drift will land in every forged repo.

**Classification:** blueprint / registry hygiene. No repo fix needed before the
first commit, but the stale plugin entries should be verified and pruned at the
source.

### Observation 10: What the blueprint already gets right

Worth recording so the fix follows the existing good pattern rather than
inventing a new one:

- `release.yml` and `ci.yml` never hardcode the owner or repo; every ref is
  derived from the `github.*` context.
- `scripts/labels.sh` resolves the repo through `gh repo view`.
- `ct.yaml` and the CI helm jobs glob `charts/*/` instead of naming the chart
  (which is also why Observation 3 bites).
- All `.tmpl` defaults listed in the lock (`CONTRIBUTING.md.tmpl`,
  `catalog-info.yaml.tmpl`, `.codecov.yml.tmpl`, `dependabot.yml.tmpl`,
  `.golangci.yml.tmpl`, `main.go.tmpl`) rendered cleanly. No unrendered `{{ }}`
  or `${ }` residue exists outside legitimate GitHub Actions, Helm, and
  git-cliff template syntax.
- `go.mod`, `mise.toml:5`, and `Dockerfile:4` agree on Go 1.26.6.
- `LICENSE` is the stock Apache 2.0 text. The trailing
  `Copyright [yyyy] [name of copyright owner]` block is the standard appendix
  explaining how to apply the license, not a placeholder that must be filled.
- All three in-place re-runs of `forge create` preserved `docs/`, which forge
  does not own.

## Conclusion

**Answer:** Yes, but the list is now short. Three forge runs and one manual
cleanup resolved the owner mismatch, the project-name rename, and the stale
directories for this repo. What remains before the first commit is entirely
blueprint residue:

1. Restore `${2}` in `charts/authz/cliff.toml:58` (Observation 4).
2. Rewrite three leaked comments and four stale instructions (Observations 5 and
   6).
3. Set the Backstage catalog values (Observation 7).
4. Create the GitHub repo as `donaldgifford/authz` (Observation 8).

Every one of those except item 4 is also a blueprint defect that will ship in
the next forged repo until fixed at the source, and the forge behaviour behind
Observation 3 will recur on any in-place re-run that changes `project_name`.

## Open Questions

Resolved during the audit: the GitHub owner is `donaldgifford`, the project name
is `authz`, and the stale directories from earlier renders are gone.

1. **What should `catalog-info.yaml` say?** Current values are `type: cli`,
   `system: dev-tools`, `lifecycle: production`.
   - (a) `type: service`, `system: <the authz platform's system name>`,
     `lifecycle: experimental` until the first real release. Set them in the
     forge variables file too so a future sync does not revert them.
   - (b) Leave as rendered and fix later. Harmless until a Backstage instance
     ingests it.

2. **How should the owner, maintainer, and catalog variables be structured in
   the registry?** Today there are three owner-shaped inputs
   (`git_provider.org`, `project_owner`, `project_component_owner`), the catalog
   fields are flat `project_component_*` keys, and every template reassembles
   repo URLs by hand. Proposal detail is in Recommendation C.
   - (a) Minimal cleanup in the same PR as the template fixes. Keep
     `git_provider` as is. Drop `project_owner`, since nothing correct renders
     from it, and keep `project_component_owner` as the single Backstage owner.
     Add a `maintainers` list of git logins for CODEOWNERS and dependabot
     assignees. Move the `type` default into each blueprint (`service` for
     `go/k8s`, `cli` for a CLI blueprint), default `lifecycle` to
     `experimental`, and make `system` optional. Lock-file impact is one removed
     key and one added list.
   - (b) Restructure as a follow-up RFC in forge-registry: a nested `catalog`
     block replacing the `project_component_*` keys, a `container_registry`
     block with `host` and `namespace`, and blueprint-level derived values
     (`repo_url`, `go_module`, `image_repo`, `chart_oci`) that templates
     reference instead of rebuilding. Removes the whole class of bug in
     Observation 1, but touches every blueprint and needs forge to support
     derived values plus a lock migration.
   - (c) Templates-only fix. Point the fifteen files at `git_provider.org` and
     change nothing else. Cheapest, and leaves the three-owner ambiguity for the
     next person.

## Recommendation

### A. This repo, before `git init`

1. Restore `${2}` in `charts/authz/cliff.toml:58` to match `cliff.toml:55`.
2. Rewrite the leaked text in `CONTRIBUTING.md`, `mise.toml`, and `security.yml`
   (Observation 5).
3. Fix the stale text: `README.md` getting-started block, `CODEOWNERS` comment,
   PR template chart wording, labeler `feature` pattern (Observation 6).
4. Set the Backstage values per Open Question 1, in both `catalog-info.yaml` and
   the forge variables file.
5. Run `just check`, `just helm-test`, `just lint-actions`, and
   `markdownlint-cli2 "**/*.md"` so the first commit is green.
6. `git init`, commit, and create the GitHub repo as `donaldgifford/authz`.

### B. forge-registry, `go/k8s` blueprint and shared defaults

1. **Render repo-location values from `git_provider`.** Every
   `github.com/<owner>/<name>` URL, the Go module path, every
   `ghcr.io/<owner>/...` ref, goreleaser's `release.github.owner`, and the
   dependabot assignees must come from `git_provider.host` and
   `git_provider.org`, not `project_owner`. That is the fifteen files in
   Observation 1's first table; the three files already using `git_provider.org`
   stay as they are. Rename `justfile`'s `project_owner` variable (line 16) to
   something like `repo_owner` so the next reader does not repeat the mistake.
   Then decide whether `project_owner` and `project_component_owner` are one
   variable or two, since only the latter reaches `catalog-info.yaml`. The bug
   is invisible whenever `project_owner` equals `git_provider.org`, which is why
   it survived until now.
2. **Prune stale variable-derived paths.** `forge create` over an existing tree
   (and `forge sync`) should record paths that embed a variable
   (`cmd/$${project_name}`, `charts/$${project_name}`) in the lock and remove or
   warn about the previous value's directory when the variable changes
   (Observation 3).
3. **Fix the `${2}` escaping** in the chart `cliff.toml` template (`$${2}`), and
   add a rendered-output check to the registry's tests that diffs the two cliff
   configs' `commit_preprocessors`.
4. **Remove copied text**: docz examples in `CONTRIBUTING.md.tmpl`, `IMPL-0021`
   in `mise.toml`, the oapi-codegen URL in `security.yml`.
5. **Align labeler with the branch convention**: `feature` head-branch pattern
   to `["^feat", "feature"]`, or document `feature/` in CONTRIBUTING. Pick one.
6. **Fix stale instructions**: `README.md` getting-started block should not tell
   the user to create `main.go`; `CODEOWNERS` comment should describe the
   rendered line; PR template should match the lockstep release contract.
7. **Default `project_component_type` to `service`** in the `go/k8s` blueprint,
   and consider `experimental` for lifecycle.
8. **Document or assert the `project_name == repo name` invariant** that
   `release.yml` depends on.
9. **Registry hygiene**: hash the `main.go.tmpl` lock entry, label `.gitignore`
   with its real source, and verify the `donald-loop` and `docker` plugin
   entries in `.claude/settings.json` still exist.
10. **Optional name-agnostic paths**: `charts/.yamllint.yml` ignore
    `charts/*/templates`; `helm.just:86` derive the k3d image ref from
    `docker-bake.hcl`'s `REGISTRY` rather than repeating it.

### C. Variable model and catalog template

Proposal for Open Question 2. The shape is option (a), with the option (b) end
state sketched so the minimal change does not have to be undone later.

**Inputs.** Four groups with non-overlapping meanings. Flat `project_*` keys
stay flat under option (a); they become blocks under (b).

| Group          | Keys                                                                       | Meaning                 | Feeds                                                                      |
| -------------- | -------------------------------------------------------------------------- | ----------------------- | -------------------------------------------------------------------------- |
| `project`      | `name`, `description`, `license`, optional `title`                         | What the thing is       | everything name-shaped                                                     |
| `git_provider` | `name`, `host`, `org`, `renovate_config_prefix`, optional `default_branch` | Where the repo lives    | module path, every repo URL, OCI namespace default, provider-specific dirs |
| `maintainers`  | list of git logins                                                         | Who to ping             | CODEOWNERS, dependabot assignees                                           |
| `catalog`      | `owner`, `type`, `lifecycle`, optional `system`                            | How Backstage models it | `catalog-info.yaml` only                                                   |

`project_owner` goes away. `catalog.owner` absorbs `project_component_owner` and
should be a full Backstage entity ref (`user:donaldgifford` or
`group:default/platform`), because a bare name resolves to a Group and a solo
maintainer is a User. `maintainers` defaults to `[git_provider.org]` for
personal accounts; for an organisation it must be set explicitly, because an org
login cannot be a dependabot assignee.

**Derived values** the blueprint computes once and templates reference by name
(as forge locals if 0.8 supports them, otherwise as the only sanctioned
expressions in templates):

```text
repo_slug  = "{{ git_provider.org }}/{{ project.name }}"
repo_url   = "https://{{ git_provider.host }}/{{ repo_slug }}"
go_module  = "{{ git_provider.host }}/{{ repo_slug }}"
image_repo = "ghcr.io/{{ git_provider.org }}/{{ project.name }}"
chart_oci  = "oci://ghcr.io/{{ git_provider.org }}/charts"
```

`go_module` must use `git_provider.host`, not a literal `github.com`, or the
Forgejo path the registry already anticipates (`.forgejo` in `.dockerignore`)
breaks on day one. `default_branch` would replace the `main` literals in the
workflow triggers (`ci`, `release`, `changelog-regen`, `codeql`,
`license-check`, `security`, `trufflehog`), `ct.yaml`, and `CONTRIBUTING.md`.

`container_registry = "ghcr"` is a selector for the per-registry release train,
which is fine. Note that `release.yml` derives the OCI namespace from
`github.repository_owner`, so the image and chart namespace is coupled to
`git_provider.org` by construction. Either document that coupling or, under
option (b), thread `container_registry.namespace` into the workflow `env` so the
two can diverge.

**Defaults that belong in the blueprint** rather than the registry-wide variable
file: `catalog.type` (`service` for `go/k8s`), `catalog.lifecycle`
(`experimental`), and the tag list (`go`, `kubernetes`, `helm`).

**`catalog-info.yaml.tmpl` changes** that stand on their own, whichever option
wins:

- Add `github.com/project-slug: <repo_slug>` when `git_provider.name == github`.
  It is the annotation the GitHub Actions, Insights, and Pull Requests plugins
  key on; `source-location` alone does not drive them.
- End `backstage.io/source-location` with `/`. Backstage resolves relative refs
  (including `techdocs-ref: dir:.`) against it as a directory, and the
  documented form is `url:https://host/org/repo/`.
- Render `spec.owner` verbatim from `catalog.owner` so the entity kind is
  explicit.
- Omit `spec.system` when `catalog.system` is empty instead of rendering a
  placeholder. A dangling system ref is a catalog error; a missing one is fine.
- Drop `metadata.title` unless `project.title` is set. A title equal to the name
  is noise. Drop `metadata.namespace: default`; it is the default.
- Either ship `mkdocs.yml` from the blueprint (docz's wiki config already
  targets it) or gate `backstage.io/techdocs-ref` on an `enable_techdocs` flag.
  Today the annotation points at a docs build that does not exist until
  `docz wiki init` runs.

## References

- `.forge-lock.hcl` (forge inputs and default-file provenance)
- `CLAUDE.md` (release contract this audit checks against)
- `github.com/donaldgifford/forge-registry`, blueprint `go/k8s`
- Design docs for the next phase: `tmpp/authz-design-doc.md` and siblings (out
  of scope here)
