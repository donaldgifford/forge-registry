---
id: DESIGN-0002
title: "Align go/std Blueprint with hclkit Conventions"
status: Draft
author: Donald Gifford
created: 2026-06-03
---
<!-- markdownlint-disable-file MD025 MD041 -->

# DESIGN 0002: Align go/std Blueprint with hclkit Conventions

**Status:** Draft
**Author:** Donald Gifford
**Date:** 2026-06-03

<!--toc:start-->
- [Overview](#overview)
- [Goals and Non-Goals](#goals-and-non-goals)
  - [Goals](#goals)
  - [Non-Goals](#non-goals)
- [Background](#background)
  - [hclkit's shape](#hclkits-shape)
  - [Current go/std state](#current-gostd-state)
  - [Gap analysis](#gap-analysis)
- [Detailed Design](#detailed-design)
  - [File inventory after alignment](#file-inventory-after-alignment)
  - [blueprint.hcl changes](#blueprinthcl-changes)
  - [Template changes](#template-changes)
    - [New templates in go/std](#new-templates-in-gostd)
    - [Templates pulled in from go/_defaults (verify they land)](#templates-pulled-in-from-godefaults-verify-they-land)
    - [Templates to adjust in go/_defaults](#templates-to-adjust-in-godefaults)
    - [Templates to remove from go/_defaults (or make opt-in)](#templates-to-remove-from-godefaults-or-make-opt-in)
    - [New templates in go/defaults (or defaults)](#new-templates-in-godefaults-or-defaults)
  - [Inheritance strategy](#inheritance-strategy)
- [API / Interface Changes](#api--interface-changes)
- [Testing Strategy](#testing-strategy)
- [Migration / Rollout Plan](#migration--rollout-plan)
- [Open Questions](#open-questions)
  - [1. Drop Makefile support from go/std scaffolds?](#1-drop-makefile-support-from-gostd-scaffolds)
  - [2. Drop standalone cliff.toml / changelog workflows in favor of goreleaser's built-in changelog: use: git-cliff?](#2-drop-standalone-clifftoml--changelog-workflows-in-favor-of-goreleasers-built-in-changelog-use-git-cliff)
  - [3. mise.toml: keep go/_defaults' broad toolchain or slim to hclkit's set?](#3-misetoml-keep-godefaults-broad-toolchain-or-slim-to-hclkits-set)
  - [4. justfile recipe set: minimal hclkit-style or richer?](#4-justfile-recipe-set-minimal-hclkit-style-or-richer)
  - [5. Share variables with homelab/go via a shared variable block / common file?](#5-share-variables-with-homelabgo-via-a-shared-variable-block--common-file)
  - [6. Should the same alignment land for go/ext and go/kubebuilder?](#6-should-the-same-alignment-land-for-goext-and-gokubebuilder)
  - [7. git_provider default: github or forgejo?](#7-gitprovider-default-github-or-forgejo)
  - [8. Where do .forgejo/workflows/ templates live — go/std or go/_defaults?](#8-where-do-forgejoworkflows-templates-live--gostd-or-godefaults)
  - [9. Backstage catalog-info.yaml.tmpl — at the registry root, go/_defaults, or go/std?](#9-backstage-catalog-infoyamltmpl--at-the-registry-root-godefaults-or-gostd)
- [References](#references)
<!--toc:end-->

## Overview

`go/std` today is a near-empty placeholder — it declares three variables
and leans entirely on `go/_defaults` for every actual file. Meanwhile,
`donaldgifford/hclkit` is the user's reference shape for what a "homelab
Go binary" repo should look like, and it carries conventions that
diverge from `go/_defaults` in meaningful ways (just-only task runner,
yamlfmt/yamllint/prettier/markdownlint configs at the project root,
Backstage `catalog-info.yaml`, gitea-label-sync `labels.yaml`, multi-arch
distroless Dockerfile, dual `.forgejo/` + `.github/` workflows).

This design plans the work to update `go/std` (and the parts of
`go/_defaults` it draws from) so that `forge create go/std <name>`
produces a scaffold that looks structurally identical to `hclkit`.

## Goals and Non-Goals

### Goals

- After scaffolding, a fresh `go/std` project matches hclkit's file
  inventory and tooling choices (justfile-only, distroless Dockerfile,
  goreleaser v2 with version/commit/date ldflags, Renovate via
  `donaldgifford/renovate-config` extends, gitea-label-sync `labels.yaml`,
  Backstage `catalog-info.yaml`).
- Linter/formatter configs (`.yamllint.yml`, `.yamlfmt.yml`,
  `.markdownlint.yaml`, `.prettierrc.yaml`, `.makefmt.yml`) ship at the
  project root — not just at the registry-defaults level.
- Dual CI surface: `.forgejo/workflows/{ci,release}.yml` as primary,
  `.github/workflows/{ci,release}.yml` as mirror, both runnable.
- Multi-arch distroless container build with cache mounts and
  `VERSION`/`COMMIT`/`DATE` build args.
- `go.mod` rendered with templated module path
  (`github.com/${project_owner}/${project_name}` or a forgejo host)
  and a pinned Go version that matches `mise.toml`.
- Sane post-create hooks: `git init`, `go mod tidy`.

### Non-Goals

- Touching the other Go blueprints (`go/ext`, `go/kubebuilder`) in this
  change. They can adopt the same conventions in follow-ups if desired.
- Migrating registry-root defaults (`_defaults/`) — those already carry
  prettier/markdownlint and we leave them. Per-project copies in the
  scaffold are additive, not in conflict.
- Renaming `go/std` to `go/hclkit` or creating a new blueprint
  category. We update the existing one in place.
- Removing Makefile support from `go/_defaults` (the existing
  `Makefile.tmpl` stays — see [Open Question 1](#open-questions)).
- Removing Renovate's dependency on `donaldgifford/renovate-config`
  (the shared config is the source of truth and stays remote).

## Background

### hclkit's shape

`donaldgifford/hclkit` is the user's working reference Go repo on
Forgejo with a GitHub mirror. The full intended layout (per its
`CLAUDE.md`) is:

```text
cmd/hclkit/main.go         # thin main, flags + dispatch
internal/                  # private library code
Dockerfile                 # multi-stage distroless build
go.mod                     # module path matches repo origin
.goreleaser.yml            # v2, multi-arch archives + checksums
mise.toml                  # toolchain (go, golangci-lint, goreleaser, ...)
justfile                   # task runner — `just` for the menu
.forgejo/workflows/ci.yml      # primary CI
.forgejo/workflows/release.yml # primary release
.github/workflows/ci.yml       # mirror CI
.github/workflows/release.yml  # mirror release
.github/workflows/pr-labels.yml
.github/labeler.yml
.claude/settings.json
.codecov.yml (TODO)
.yamllint.yml
.yamlfmt.yml
.markdownlint.yaml
.prettierrc.yaml
.makefmt.yml
.gitignore
catalog-info.yaml          # Backstage component
labels.yaml                # gitea-label-sync
renovate.json5             # extends donaldgifford/renovate-config:*
CLAUDE.md
README.md
```

Files referenced in `CLAUDE.md` but **not yet committed to hclkit**:
`Dockerfile`, both `ci.yml`/`release.yml` pairs, `cmd/hclkit/main.go`,
`internal/`. We treat the documented intent as the source of truth.

Distinctive choices vs. our current `go/_defaults`:

- **No Makefile.** Just-only task runner.
- **No cliff/changelog automation.** goreleaser drives changelogs via
  `changelog: use: git-cliff`, but there's no separate cliff.toml at
  the project root and no changelog-regen workflow.
- **Renovate via remote extends**, not a project-local config.
- **Labels via gitea-label-sync `labels.yaml`**, with a `just labels-sync`
  recipe.
- **Backstage `catalog-info.yaml`** for service catalog ingestion.
- **goreleaser v2** with `formats: [tar.gz]` (slice form, the v1 →
  v2 migration shape).

### Current go/std state

`go/std/blueprint.hcl` declares:

- `project_name` (kebab-case, required)
- `project_owner` (kebab-case, required)
- `project_description` (required)

No template files at all. `go/std/${project_name}/README.md.tmpl` and
the rename block were removed in the flatten refactor (PR #11).
Everything is inherited from `go/_defaults`:

- Build/test: `Makefile.tmpl` + `justfile.tmpl` (both shipped).
- Lint: `.golangci.yml.tmpl`, plus the registry-root linter configs.
- Release: `.goreleaser.yml.tmpl`, `cliff.toml.tmpl`,
  changelog/release/license-check workflows.
- Source: `cmd/${project_name}/main.go.tmpl`.
- CI: `.github/workflows/ci.yml` with golangci-lint + test + build
  jobs and an actionlint job.

### Gap analysis

Below, **add** means "ship at the scaffolded project root via go/std or
go/_defaults"; **adjust** means "modify an existing template";
**remove from default scaffold** means "drop from the rendered output"
(may or may not delete from the registry, see Open Questions).

| Concern | hclkit | go/std (current) | Action |
|---|---|---|---|
| Task runner | justfile only | justfile + Makefile | Adjust — see [Open Question 1](#open-questions) |
| `go.mod` | committed, pinned Go version | not scaffolded | **Add** `go.mod.tmpl` |
| `Dockerfile` | distroless, BuildKit cache mounts, `VERSION`/`COMMIT`/`DATE` args | not scaffolded | **Add** `Dockerfile.tmpl` (mirrors `go/ext` style but simpler) |
| `catalog-info.yaml` | shipped | not scaffolded | **Add** `catalog-info.yaml.tmpl` |
| `labels.yaml` (gitea-label-sync) | shipped | not scaffolded; `scripts/labels.sh` exists but unused at root | **Add** `labels.yaml.tmpl` + `labels-sync` just recipe |
| Backstage techdocs | implied via `catalog-info.yaml` annotation | n/a | Covered by `catalog-info.yaml` add |
| `.yamllint.yml` | at project root | only at registry-root `_defaults/` | **Add** `.yamllint.yml` to `go/_defaults` |
| `.yamlfmt.yml` | at project root | only at registry-root `_defaults/` | **Add** `.yamlfmt.yml` to `go/_defaults` |
| `.markdownlint.yaml` | at project root | at registry-root `_defaults/` | Already inherited — verify it lands |
| `.prettierrc.yaml` | at project root | at registry-root `_defaults/` | Already inherited — verify it lands |
| `.makefmt.yml` | at project root | at registry-root `_defaults/` | **Remove** from `go/_defaults` if Makefile dropped (see Open Question 1) |
| `.forgejo/workflows/ci.yml` | intended primary | not in go/_defaults | **Add** to `go/std` or `go/_defaults` |
| `.forgejo/workflows/release.yml` | intended primary | not in go/_defaults | **Add** to `go/std` or `go/_defaults` |
| `.github/workflows/ci.yml` | intended mirror | shipped (different shape) | **Adjust** to match hclkit's just-driven shape |
| `.github/workflows/release.yml` | intended mirror | shipped (cliff/license driven) | **Adjust** to a goreleaser-only flow |
| `.goreleaser.yml` | v2, `formats: [tar.gz]`, `git-cliff` changelog, optional `gitea_urls` | v2-templated with goreleaser braces, archives use `format: "tar.gz"` (singular) | **Adjust** to slice form + commented `gitea_urls` block + ldflags include `main.date` |
| `cliff.toml` | not present (goreleaser uses git-cliff via `use: git-cliff` directly) | shipped at scaffold | **Remove from scaffold** — see [Open Question 2](#open-questions) |
| Changelog workflows | not present | shipped (`changelog.yml`, `changelog-regen.yml`) | **Remove from scaffold** if cliff dropped — see Open Question 2 |
| `.golangci.yml` | not in tree | shipped at scaffold (templated owner) | Keep — golangci-lint is in mise.toml; hclkit just hasn't committed one yet |
| `.codecov.yml` | not yet | shipped | Keep, harmless |
| Renovate | `extends: ["github>donaldgifford/renovate-config", ...]` (5 extends) | shipped, but in `go/_defaults` already extends similarly | Verify match |
| `mise.toml` | minimal Go-focused (just, go, golangci-lint, goreleaser, markdownlint, yamlfmt, yamllint, prettier) | broader (cobra-cli, goimports, mockery, godoc, makefmt, checkmake, git-cliff, actionlint, yq, jq, docz, syft, govulncheck, go-licenses, helm) | **Adjust** — slim to hclkit's set for go/std, leave fuller list in go/_defaults? See [Open Question 3](#open-questions) |
| `justfile` recipes | `build`, `test`, `run`, `lint` (golangci+yaml+md+prettier), `fmt` (gofmt+yamlfmt+prettier), `release` (tag+push) | richer set (build-core, test-pkg/coverage/report, lint-fix/config/actions, license, release-check/local) | **Adjust** to align — see [Open Question 4](#open-questions) |

## Detailed Design

### File inventory after alignment

Goal scaffold output for `forge create go/std my-tool`
(`my-tool` represents the `project_name`):

```text
my-tool/
├── CLAUDE.md                          # templated, per-project shape
├── README.md                          # templated quickstart
├── Dockerfile                         # multi-stage distroless build
├── go.mod                             # templated module path + Go pin
├── catalog-info.yaml                  # Backstage component
├── labels.yaml                        # gitea-label-sync
├── justfile                           # task runner
├── mise.toml                          # pinned toolchain
├── renovate.json5                     # extends shared config
├── .goreleaser.yml                    # v2, multi-arch + git-cliff
├── .gitignore                         # Go-shaped
├── .yamllint.yml                      # YAML lint
├── .yamlfmt.yml                       # YAML fmt
├── .markdownlint.yaml                 # MD lint
├── .prettierrc.yaml                   # MD prose wrap
├── .makefmt.yml                       # IF Makefile retained
├── .claude/settings.json              # Claude Code permissions
├── .forgejo/workflows/
│   ├── ci.yml                         # primary CI
│   └── release.yml                    # primary release
├── .github/
│   ├── labeler.yml                    # PR labeler config
│   └── workflows/
│       ├── ci.yml                     # mirror CI
│       ├── release.yml                # mirror release
│       └── pr-labels.yml              # label requirement check
├── cmd/my-tool/
│   └── main.go                        # thin main, version metadata
└── internal/
    └── .gitkeep                       # placeholder for library code
```

### blueprint.hcl changes

Add variables to support templating module paths and CI behavior:

```hcl
variable "git_provider" {
  description = "Primary git provider (drives module path + workflow defaults)"
  type        = "choice"
  choices     = ["github", "forgejo"]
  default     = "github"
}

variable "git_host" {
  description = "Hostname of the git provider"
  type        = "string"
  default     = "${git_provider == \"forgejo\" ? \"git.fartlab.dev\" : \"github.com\"}"
}

variable "project_org" {
  description = "Org/user owning the repo (separate from project_owner for forge mirroring)"
  type        = "string"
  default     = "${project_owner}"
}

variable "go_version" {
  description = "Go toolchain version (must match mise.toml + go.mod directive)"
  type        = "string"
  default     = "1.26.3"
}

hooks {
  post_create = ["git init", "go mod tidy"]
}
```

`project_name`, `project_owner`, `project_description`, `license`
stay as today.

Note: this overlaps heavily with `homelab/go`'s variable shape. See
[Open Question 5](#open-questions) about whether to share or keep
distinct.

### Template changes

#### New templates in `go/std`

- `go.mod.tmpl` — `module ${git_host}/${project_org}/${project_name}` /
  `go ${go_version}`
- `Dockerfile.tmpl` — multi-stage; `golang:${go_version}` builder,
  `gcr.io/distroless/static-debian12:nonroot` runtime; `VERSION` /
  `COMMIT` / `DATE` ARGs surfaced via ldflags; BuildKit cache mounts
  for `/go/pkg/mod` + `/root/.cache/go-build`.
- `catalog-info.yaml.tmpl` — Backstage Component referencing
  `${git_host}/${project_org}/${project_name}`, techdocs annotation
  `dir:.`.
- `labels.yaml.tmpl` — gitea-label-sync schema, copied from hclkit
  (bug/enhancement/documentation/chore/dependencies/needs-review/
  do-not-merge/breaking-change).
- `.forgejo/workflows/ci.yml.tmpl` — runs `just test` + `just lint`
  on push/PR.
- `.forgejo/workflows/release.yml.tmpl` — fires on `v*` tags,
  installs mise, runs `goreleaser release --clean` with `GITEA_TOKEN`.
- (Repeat for `.github/workflows/{ci,release}.yml`, swapping
  `GITHUB_TOKEN` and removing the gitea_urls dance.)
- `.gitignore` — Go-shaped (`*.test`, `*.out`, `coverage.txt`,
  `coverage.html`, `/bin/`, `/dist/`, `/${project_name}`, `.env*`,
  IDE dirs).

#### Templates pulled in from `go/_defaults` (verify they land)

- `.claude/settings.json` (inherited from registry-root `_defaults`
  via go/_defaults override)
- `.markdownlint.yaml`, `.prettierrc.yaml` (inherited from
  registry-root `_defaults`)
- `cmd/${project_name}/main.go.tmpl`
- `mise.toml.tmpl`, `justfile.tmpl`, `.goreleaser.yml.tmpl`,
  `.golangci.yml.tmpl`, `renovate.json5`

#### Templates to adjust in `go/_defaults`

- `justfile.tmpl` — see [Open Question 4](#open-questions).
- `mise.toml.tmpl` — see [Open Question 3](#open-questions).
- `.goreleaser.yml.tmpl`:
  - `archives[].format: "tar.gz"` → `formats: [tar.gz]`
  - Add `-X main.date={{ .Date }}` ldflag
  - Add commented `release.gitea_urls` stanza
  - Switch `changelog.use: github` → `use: git-cliff` if we drop the
    standalone cliff.toml (Open Question 2)
- `.github/workflows/ci.yml` — replace cliff/license-heavy steps with
  a `just test` + `just lint` flow that mirrors hclkit
- `.github/workflows/release.yml` — switch to goreleaser-only flow

#### Templates to remove from `go/_defaults` (or make opt-in)

- `Makefile.tmpl` — if Makefile dropped (Open Question 1)
- `cliff.toml.tmpl`, `CHANGELOG.md`, `changelog.yml`,
  `changelog-regen.yml` — if cliff dropped (Open Question 2)
- `.codecov.yml` — debatable, keep for now
- `dependabot.yml` — Renovate is the SoT; remove

#### New templates in `go/_defaults` (or `_defaults`)

- `.yamllint.yml`, `.yamlfmt.yml` — already at registry-root
  `_defaults/`; verify they land in the scaffold without duplication.

### Inheritance strategy

Three-tier inheritance: `_defaults/` (registry root) →
`go/_defaults/` (category) → `go/std/` (blueprint). Last wins.

Most of the linter configs (`.yamllint.yml`, `.markdownlint.yaml`,
`.prettierrc.yaml`, `.yamlfmt.yml`, `.makefmt.yml`) already exist in
the registry-root `_defaults/`. We should rely on inheritance rather
than duplicating them in `go/_defaults`. Things that are
Go-specific (justfile, mise, goreleaser, golangci, gitignore Go bits)
live in `go/_defaults`. Things that are unique to `go/std`'s shape
vs other Go blueprints (`go.mod`, `Dockerfile`, `catalog-info.yaml`,
`labels.yaml`, `.forgejo/`) live in `go/std/` directly.

This is debatable — `go/ext` and `go/kubebuilder` arguably want some
of these too. See [Open Question 6](#open-questions).

## API / Interface Changes

User-facing changes when running `forge create go/std <name>`:

- New required prompts: `git_provider` (choice, default `github`),
  optional `git_host` / `project_org` / `go_version` (all defaulted).
- `go.mod` is created with a real module path — first
  `go mod tidy` (post-create hook) succeeds without manual edits.
- The scaffolded project builds the Dockerfile out of the box (no
  manual `cmd/<name>/main.go` write needed — main is templated).
- `just labels-sync` recipe added (requires `GITEA_TOKEN` /
  `GITHUB_TOKEN` env var).

Blueprint version bump: `0.1.0` → `0.2.0` (additive variables +
new files = minor bump).

## Testing Strategy

Per the registry conventions, validation is structural, not behavioral.
The verification plan:

1. `forge create go/std test-std --defaults` succeeds, post-create
   hooks run, `go mod tidy` resolves with no errors.
2. The rendered project tree matches the inventory in
   [File inventory after alignment](#file-inventory-after-alignment).
3. Diff the rendered output file-by-file against `hclkit`'s tree
   (modulo project name) and document any intentional deviations.
4. `cd <rendered>; just test` and `just lint` both pass on the empty
   scaffold.
5. `goreleaser check` passes on the rendered `.goreleaser.yml`.
6. `actionlint .github/workflows/*.yml .forgejo/workflows/*.yml`
   passes.
7. `/registry-validate` reports clean.
8. Build the Docker image locally: `docker build -t test-std:dev .` —
   completes and the image runs (`docker run --rm test-std:dev`
   should exit cleanly with a usage line or version output).

## Migration / Rollout Plan

This is an additive change for new scaffolds — existing scaffolded
projects are unaffected unless they `forge sync` (which they would
opt into deliberately).

Two phases:

**Phase 1 — Blueprint additions (this design's scope).** Add the new
template files to `go/std` and adjust `go/_defaults` as outlined.
Bump `go/std` version to `0.2.0`. Land in one PR.

**Phase 2 — Validate against a real repo (follow-up).** Cut a fresh
`hclkit2`-style repo from the updated blueprint, diff against
`hclkit`, fix any remaining deltas, and (if hclkit is willing) push
the updated scaffold back into hclkit itself via `forge sync`.

## Open Questions

Each question lists my recommendation as **option (a)** with
alternatives. Pick a letter or write in.

### 1. Drop Makefile support from go/std scaffolds?

hclkit is just-only. `go/_defaults` ships both `justfile.tmpl` and
`Makefile.tmpl` today. Keeping both means duplicated recipes and
`.makefmt.yml` shipping for a tool nobody uses if they never invoke
`make`.

- **a.** Drop `Makefile.tmpl` and `.makefmt.yml` from the rendered
  go/std scaffold (still keep them in `go/_defaults` for `go/ext` /
  `go/kubebuilder` to inherit if those keep makefiles). Recommended:
  matches hclkit, less churn for users not using make.
- **b.** Drop them from `go/_defaults` entirely (any blueprint that
  wants a Makefile would have to add one back).
- **c.** Keep both in go/std for users who want them.

### 2. Drop standalone cliff.toml / changelog workflows in favor of goreleaser's built-in `changelog: use: git-cliff`?

hclkit uses goreleaser's built-in `use: git-cliff` and has no
standalone `cliff.toml` or changelog-regen workflow. `go/_defaults`
ships a `cliff.toml.tmpl`, `CHANGELOG.md`, `changelog.yml`,
`changelog-regen.yml` — a parallel system that emits a `CHANGELOG.md`
on every push to main.

- **a.** Drop the standalone cliff system from the go/std scaffold
  (leave the templates in `go/_defaults` until we audit go/ext and
  go/kubebuilder, since they may want a different answer). The
  goreleaser-driven changelog is enough for hclkit's use case.
  Recommended.
- **b.** Keep cliff for go/std too — `CHANGELOG.md` is useful even
  without releases.
- **c.** Drop cliff from `go/_defaults` entirely and rip out
  `cliff.toml.tmpl` everywhere. (Big enough to be its own design.)

### 3. mise.toml: keep go/_defaults' broad toolchain or slim to hclkit's set?

`go/_defaults/mise.toml.tmpl` pins ~20 tools (cobra-cli, goimports,
mockery, godoc, makefmt, checkmake, git-cliff, actionlint, yq, jq,
docz, syft, govulncheck, go-licenses, helm, …). hclkit pins 8
(just, go, golangci-lint, goreleaser, markdownlint-cli2, yamlfmt,
yamllint, prettier).

- **a.** Override in `go/std` with a slim hclkit-aligned `mise.toml.tmpl`
  (just, go, golangci-lint, goreleaser, markdownlint-cli2, yamlfmt,
  yamllint, prettier, **plus** actionlint since the blueprint ships
  workflows). Keep the broader set in `go/_defaults` for `go/ext` /
  `go/kubebuilder`. Recommended — keeps the scaffold quick to install.
- **b.** Slim `go/_defaults/mise.toml.tmpl` to hclkit's set (forces
  go/ext/go/kubebuilder to add their own back).
- **c.** Keep the broad set — extra tools don't hurt.

### 4. justfile recipe set: minimal hclkit-style or richer?

hclkit's justfile has 5 recipes (`build`, `test`, `run`, `lint`,
`fmt`, `release`). `go/_defaults/justfile.tmpl` has ~25 (split by
build/run/test/lint/license/release/gate groups).

- **a.** Slim `go/_defaults/justfile.tmpl` toward hclkit's shape but
  keep the most useful extras: `test-coverage`, `lint-actions`,
  `lint-fix`, `release-check`, `release-local`, `labels-sync` (new),
  `check` composite. Drop the rarely-used: `test-all`, `test-pkg`,
  `test-report`, `lint-config`, `license-check`, `license-report`,
  `run-local`. Recommended — preserves the useful tooling without
  the bloat.
- **b.** Adopt hclkit's exact 5-recipe set verbatim (drop everything
  else).
- **c.** Keep the full current set.

### 5. Share variables with homelab/go via a shared `variable` block / common file?

`homelab/go` already declares `git_provider` / `git_host` /
`project_org` / `renovate_config_prefix` / `go_version` exactly the
same way this design proposes for `go/std`. Forge doesn't have a
"shared variable" import as far as I've seen — the options are
duplicate or merge.

- **a.** Duplicate the variable declarations. forge's
  `_defaults`-style inheritance doesn't extend to `variable` blocks
  (only files), so this is the path of least resistance. Each
  blueprint owns its variables explicitly, which is also clearer for
  the user filling out prompts. Recommended.
- **b.** Pull `git_provider` / `git_host` etc. into
  `go/_defaults/blueprint.hcl` if that's a thing (need to verify
  forge supports category-level variable inheritance).
- **c.** Make `go/std` extend `homelab/go` somehow (probably not
  possible).

### 6. Should the same alignment land for go/ext and go/kubebuilder?

This design only touches `go/std`. `go/ext` and `go/kubebuilder` would
benefit from many of the same additions (Dockerfile already exists in
both; `.forgejo/workflows/`, `catalog-info.yaml`, `labels.yaml`,
yaml/md linter configs at project root are missing).

- **a.** Out of scope here — land go/std first, then do a follow-up
  pass for go/ext and go/kubebuilder once the shape is validated
  against hclkit. Recommended.
- **b.** Bundle all three in this design — they share enough that
  doing them together avoids triple-touching `go/_defaults`.
- **c.** Skip go/std entirely and do go/_defaults' shared bits +
  hclkit's specific files as a new `go/binary` blueprint, leaving
  go/std as the minimal placeholder it is today.

### 7. `git_provider` default: github or forgejo?

hclkit lives on Forgejo with GitHub as mirror. `homelab/go` defaults
`git_provider` to forgejo. `go/std` is a more general blueprint —
most public consumers are on GitHub.

- **a.** Default to `github` for go/std. Users on Forgejo override.
  Recommended — matches the broader-audience framing of `go/std`
  vs the homelab-specific framing of `homelab/go`.
- **b.** Default to `forgejo` to match hclkit and `homelab/go`.
- **c.** Make it required (no default) so the user explicitly chooses.

### 8. Where do `.forgejo/workflows/` templates live — `go/std` or `go/_defaults`?

The shared go/_defaults already carries `.github/workflows/*` (so
both `go/std` and `go/ext` get them). `.forgejo/workflows/` doesn't
exist there yet.

- **a.** Add `.forgejo/workflows/{ci,release}.yml.tmpl` to
  `go/_defaults` so future Go blueprints inherit the dual-provider
  shape too. Use a condition to exclude when `git_provider == "github"`,
  matching homelab/go's pattern. Recommended.
- **b.** Add only to `go/std`. Other Go blueprints can opt-in by
  adding their own when they need it.
- **c.** Skip `.forgejo/` workflows entirely for `go/std` — leave
  hclkit-style dual workflows to `homelab/go` only.

### 9. Backstage `catalog-info.yaml.tmpl` — at the registry root, go/_defaults, or go/std?

Backstage is org-level tooling that's not Go-specific — every
blueprint of every category arguably wants it.

- **a.** Add to `go/std` only for now. Promote to a higher level
  once other categories adopt it (avoid premature factoring).
  Recommended.
- **b.** Add to `_defaults/` (registry root) so every blueprint
  emits a `catalog-info.yaml` by default.
- **c.** Add to `go/_defaults` so all Go blueprints get it.

## References

- [DESIGN-0001](./0001-claude-code-skills-for-forge-registry-management.md)
- [donaldgifford/hclkit](https://github.com/donaldgifford/hclkit) —
  source-of-truth reference repo
- [donaldgifford/renovate-config](https://github.com/donaldgifford/renovate-config) —
  upstream renovate extends
- `homelab/go/blueprint.hcl` — sibling Go blueprint with the same
  `git_provider`-driven variable shape, useful precedent
- `go/_defaults/` — current inheritance layer being adjusted
