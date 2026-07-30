---
id: DESIGN-0003
title: "Bun Registry: bun/std Blueprint Shape"
status: Draft
author: Donald Gifford
created: 2026-06-30
---
<!-- markdownlint-disable-file MD025 MD041 -->

# DESIGN 0003: Bun Registry: bun/std Blueprint Shape

**Status:** Draft
**Author:** Donald Gifford
**Date:** 2026-06-30

<!--toc:start-->
- [Overview](#overview)
- [Goals and Non-Goals](#goals-and-non-goals)
  - [Goals](#goals)
  - [Non-Goals](#non-goals)
- [Background](#background)
  - [Reference repos](#reference-repos)
  - [Current bun/ state — and the contamination](#current-bun-state--and-the-contamination)
  - [Gap analysis](#gap-analysis)
- [Detailed Design](#detailed-design)
  - [Target shape (rfc-site aligned)](#target-shape-rfc-site-aligned)
  - [File inventory after alignment](#file-inventory-after-alignment)
  - [blueprint.hcl changes](#blueprinthcl-changes)
  - [Inheritance strategy](#inheritance-strategy)
  - [Renovate annotations](#renovate-annotations)
- [API / Interface Changes](#api--interface-changes)
- [Testing Strategy](#testing-strategy)
- [Migration / Rollout Plan](#migration--rollout-plan)
- [Open Questions](#open-questions)
- [References](#references)
<!--toc:end-->

## Overview

A new `bun/` registry was added with `bun/std` and `bun/_defaults`, but
the current files are a copy-paste mash-up — `bun/_defaults/justfile.tmpl`
is literally Go's (golangci-lint, goimports, goreleaser), `bun/std`
hardcodes `"rfc-site"` and `"ShitWiz UI"` strings, and there's no
coherent shape for what a fresh `bun/std` scaffold should produce.

This design picks the rfc-site shape (React 19 + RR7 SSR + Vite +
Vitest + ESLint + Prettier + TypeScript, with `bun` as runtime/package
manager) as the canonical reference, and lays out the cleanup +
templating needed to make `forge create bun/std <name>` produce a
scaffold that mirrors rfc-site (minus rfc-site-specific bits like
orval and the API client).

## Goals and Non-Goals

### Goals

- `forge create bun/std my-app` produces a runnable scaffold:
  `bun install && bun run dev` brings up Vite, `bun run test` runs
  Vitest, `bun run lint` passes ESLint, `docker buildx bake` builds
  a multi-arch image.
- File structure mirrors rfc-site as closely as practical, with
  hardcoded project-specific strings replaced by template variables.
- Docker integration: multi-stage `Dockerfile` (dev hot-reload +
  Caddy static prod), `docker-bake.hcl.tmpl` for multi-arch, a
  generic `docker-compose.yml` for local testing, and a `docker.just`
  import (matching the `go/docker` pattern).
- `bun/_defaults/justfile.tmpl` is a real Bun justfile (rewritten
  from scratch — current copy is Go's).
- `bunfig.toml` shipped with sane defaults.
- All Bun-relevant tool pins in `mise.toml` carry Renovate
  annotation comments so updates flow automatically.

### Non-Goals

- Designing a separate `bun/api` or `bun/cli` blueprint for the
  backstage-api shape (Biome + `bun test` + native `bun build`).
  Acknowledged but deferred — see [Open Question 1](#open-questions).
- Building a starter app scaffold (`src/`, routes, components).
  We emit `src/.gitkeep` and document the next step; the user wires
  their own app code.
- Migrating registry-root linter configs (`.markdownlint.yaml`,
  `.prettierrc.yaml`, `.yamllint.yml`, `.yamlfmt.yml`) — those
  already exist at `_defaults/` and are inherited.
- Touching the existing `go/*`, `rust/*`, `homelab/*`, `std/*`
  blueprints. This is bun-only.

## Background

### Reference repos

The user named two example Bun/TS repos. They diverge in major
toolchain choices, so we have to pick one shape for `bun/std`:

| Concern | `rfc-site` | `backstage-api` |
|---|---|---|
| Framework | React 19 + React Router 7 SSR | Bun HTTP server, hapi-extras |
| Build | `react-router build` (Vite-driven) | `bun build src/index.ts --outdir ./dist --target bun` |
| Tests | `vitest` + jsdom + Testing Library | `bun test` (native) |
| Lint/format | ESLint flat config + Prettier | **Biome** (single binary, lint+format) |
| TypeScript | strict + RR7 type generation | strict + plain `tsc --noEmit` |
| Special tooling | `orval` (OpenAPI → TS client), MSW for dev mocking | hapi, Bun TUI via Ink |
| Container | none committed | multi-stage Dockerfile + Helm chart + ArgoCD manifests |
| CI shape | single `check` job: typecheck → lint → format-check → test → build | per-tool jobs (lint, typecheck, test) |

The user requested we follow **rfc-site** ("testing framework, linter,
etc. like what's in the rfc-site"). That means: **Vite + Vitest + ESLint
+ Prettier + TypeScript strict**, with Bun as the runtime/package
manager. backstage-api's Biome + `bun test` + native build is
explicitly out of scope for `bun/std` — see Open Question 1 for
whether a sibling blueprint should cover that shape later.

### Current bun/ state — and the contamination

`bun/std/` (committed but mostly wrong):

| File | State |
|---|---|
| `blueprint.hcl` | Only declares `project_name` + `license`. Missing `project_owner`/`project_description`/etc. Has `rename` block for `${project_name}/` wrapper (the pattern we just deleted from every other blueprint in PR #11) |
| `package.json` | **Hardcoded `"name": "rfc-site"`**, hardcoded description, copy of rfc-site's full dep list including orval/msw/shiki/mermaid (project-specific) |
| `tsconfig.json` | rfc-site's verbatim — includes `.react-router/types`, `noUncheckedIndexedAccess`, etc. (mostly OK as a strict baseline) |
| `vite.config.ts` | rfc-site's — pulls in `@react-router/dev/vite` plugin |
| `vitest.config.ts` | rfc-site's — has rfc-site-specific comment about Shiki cold-start; jsdom env, react dedupe, 15s timeout |
| `eslint.config.js` | rfc-site's — solid flat config, scoped to `src/` + `tests/`, ignores rfc-site's `src/portal/api/__generated__` (project-specific) |
| `justfile` | rfc-site's — references `gen-api` / `gen-api-check` which are rfc-site-only |
| `Dockerfile` | Copy-paste from "ShitWiz UI" — multi-stage with Caddy prod stage. Mostly OK shape; needs string scrub |
| `docker-bake.hcl.tmpl` | Adapted from go/ext — good shape, uses `${project_name}` correctly |
| `justfile.docker.tmpl` | Same as `go/docker/docker.just.tmpl`. Should be named `docker.just.tmpl` to match the import name in justfile |
| `docker-compose.yml` | Hardcoded "ShitWiz" service names + `shitwiz_shitwiz-demo` external network |
| `mise.toml` | Confused mix — has bun/node (good) + helm/cosign/promtool/git-cliff/checkmake/makefmt (don't belong in a TS project) |
| `charts/`, `ct.yaml` | Helm chart-testing leftover from go/ext copy. **Delete** |
| `react-router.config.ts`, `orval.config.ts` | rfc-site-specific. **Delete** |
| `.dockerignore` | Generic — keep |

`bun/_defaults/` (committed but largely wrong):

| File | State |
|---|---|
| `justfile.tmpl` | **Literally Go's justfile** (golangci-lint, goimports, goreleaser, allowed_licenses). Must be rewritten from scratch |
| `CLAUDE.md.tmpl` | **Literally Go's CLAUDE** ("Go binary maintained as part of the homelab fleet", `slog` guidance, `go mod tidy`, etc.) |
| `mise.toml` | Has bun/node (good) but also helm/cosign/promtool/git-cliff/makefmt/checkmake which are Go-fleet tools, not TS tools |
| `bunfig.toml` | One liner: `[test] preload = ["./tests/setup.ts"]` — fine but presumes Vitest setup file convention |
| `.prettierrc.yaml` AND `.prettierrc.json` | **Both exist** — Prettier reads the first one found in priority order, which is ambiguous. Pick one. rfc-site uses `.prettierrc.json`. See Open Question 2 |
| `.prettierignore` | Empty — fine |
| `catalog-info.yaml.tmpl` | Has `tags: [go]` and forgejo-flavored URL — needs `tags: [bun, typescript]` and github default |
| `cliff.toml.tmpl` | Standalone git-cliff config. See Open Question 3 |
| `renovate.json5.tmpl` | extends `renovate-config:node` `:docker` `:helm` `:mise` `:ci` — looks correct |
| `.github/workflows/*` | 11 workflows — most copied from Go fleet. CI shape needs to be rfc-site's (single `check` job) |
| `.github/dependabot.yml` | Redundant with Renovate. Remove |
| `.github/licenses-csv.tpl` | Go-licenses template. Remove (no go-licenses in TS world) |
| `.github/CODEOWNERS` | Generic — keep |
| `.codecov.yml` | Generic — keep |
| `.docz.yaml` | Generic — keep |
| `.markdownlint.yaml`, `.yamllint.yml`, `.yamlfmt.yml` | Universal lint configs — these already exist at registry-root `_defaults/`. **Remove from bun/_defaults** and rely on inheritance |
| `CHANGELOG.md` | Empty/placeholder — see Open Question 3 |
| `scripts/labels.sh` | Generic label sync — keep |

### Gap analysis

| Concern | rfc-site | bun/std (current) | Action |
|---|---|---|---|
| `package.json` | rfc-site-specific deps + scripts | hardcoded rfc-site deps | **Rewrite** as a generic React+RR7+Vite+Vitest+ESLint+Prettier shell, no orval/msw/shiki/mermaid; templated `name`/`description`/`license` |
| `bunfig.toml` | not present at root | one-liner in `_defaults` | Keep `_defaults` version; document what other knobs exist |
| `tsconfig.json` | strict + RR7 types | rfc-site's verbatim | Keep — solid strict baseline |
| `vite.config.ts` | RR7 plugin | RR7 plugin | Keep |
| `vitest.config.ts` | jsdom + react dedupe + 15s timeout | rfc-site's with rfc-site-specific comment | Keep shape, scrub rfc-site comment, drop project-specific `src/**/index.ts` exclude |
| `eslint.config.js` | flat config, React 19 + jsx-a11y + RR ignores | rfc-site's | Keep shape, replace rfc-site's `__generated__` ignore with a generic comment about how to extend |
| `react-router.config.ts` | rfc-site has it | bun/std has it (no template needed) | Keep — RR7 needs it |
| `justfile` | rfc-site recipes (dev/dev:msw/build/start/typecheck/lint/format/test/gen-api) | rfc-site-aligned | **Rewrite** in `bun/_defaults/justfile.tmpl` (currently it's Go's). Drop rfc-site-specific recipes (gen-api*, dev:msw) |
| `docker.just` recipes | none (rfc-site has no Dockerfile) | `justfile.docker.tmpl` exists | Keep — rename to `docker.just.tmpl` to match the import name |
| `Dockerfile` | none (rfc-site doesn't have one) | "ShitWiz UI" hardcoded | **Rewrite** as generic templated multi-stage (dev / builder / Caddy prod) using `${project_name}` everywhere |
| `docker-bake.hcl` | none | exists, well-formed | Keep |
| `docker-compose.yml` | none | "shitwiz" service names + external network | **Rewrite** generic with `${project_name}` services, no external network requirement |
| `mise.toml` | bun/node + universal linters | confused mix with helm/cosign/promtool/etc | **Rewrite** — bun + node + just + actionlint + linter set (markdownlint/yamlfmt/yamllint/prettier). Drop Go-fleet stuff |
| `renovate.json5` | not in rfc-site (rfc-site has none) | in `_defaults` extending shared config with `:node` | Keep |
| Renovate `# renovate:` annotations on `mise.toml` | yes | yes in `_defaults` | Verify these survive the rewrite |
| CI workflow | single `check` job that does typecheck → lint → format-check → test → build (no docker) | 11 workflows from Go fleet (changelog-regen, license-check, codeql, security, trufflehog, etc.) | **Slim** to: `ci.yml` (rfc-site shape), `release.yml` (docker build+push on tag), `pr-labels.yml`, `trufflehog.yml`, `codeql.yml`. Drop license-check (no go-licenses equivalent for npm by default), dependabot.yml (Renovate), changelog-regen.yml (see Open Question 3) |
| `.prettierrc.*` | `.prettierrc.json` | both `.json` and `.yaml` exist | **Delete `.prettierrc.yaml`**, keep `.prettierrc.json` (matches rfc-site) |
| `CLAUDE.md` | per-repo doc | Go-copied template | **Rewrite** for Bun/TS shape |
| `catalog-info.yaml` | not in rfc-site | exists in `_defaults` with `tags: [go]` | Keep — adjust tags to `[bun, typescript, react]` |
| Backstage techdocs annotation | n/a | `dir:.` | Keep |
| `.codecov.yml` | not in rfc-site | exists | Keep — harmless |

## Detailed Design

### Target shape (rfc-site aligned)

Single blueprint `bun/std` produces a React 19 + RR7 SSR webapp
skeleton. The user owns adding routes, components, and (optionally)
an OpenAPI client. The blueprint provides:

- Toolchain pinned via `mise.toml` (bun + node + linters).
- Dependencies installed via `bun install` (post-create hook).
- Vite dev server + Vitest test runner + ESLint strict + Prettier.
- Docker stack: multi-stage Dockerfile (dev with HMR, Caddy static
  prod), `docker-bake.hcl` for multi-arch, `docker-compose.yml` for
  local testing.
- Justfile mirrors `package.json` scripts + imports `docker.just`
  for the docker recipes.
- Renovate via shared `extends` (already wired in `_defaults`).
- Backstage catalog entry, gitea/github labels via `labels.yaml`.
- CI mirroring rfc-site's single-`check`-job pattern + a separate
  `release.yml` for docker image publish on tag.

### File inventory after alignment

```text
my-app/
├── CLAUDE.md                          # per-repo Bun/TS shape (rewritten)
├── README.md                          # templated quickstart
├── package.json                       # templated name/desc/license + generic deps
├── tsconfig.json                      # strict, RR7-aware
├── bunfig.toml                        # [test] preload = setup.ts
├── bun.lock                           # generated by post-create `bun install`
├── vite.config.ts                     # RR7 plugin
├── vitest.config.ts                   # jsdom + react dedupe
├── react-router.config.ts             # RR7 config
├── eslint.config.js                   # flat config, React 19
├── .prettierrc.json                   # rfc-site's prettier shape
├── .prettierignore
├── Dockerfile                         # multi-stage dev/builder/prod
├── docker-bake.hcl                    # multi-arch
├── docker-compose.yml                 # dev/demo services, no external network
├── docker.just                        # docker recipes (imported by justfile)
├── justfile                           # mirrors package.json + imports docker.just
├── mise.toml                          # bun + node + linters with renovate annotations
├── renovate.json5                     # extends shared config
├── catalog-info.yaml                  # Backstage component
├── labels.yaml                        # github-label-sync
├── .gitignore                         # TS/Node + Bun + Vite/RR7 + Docker
├── .dockerignore                      # Bun-shaped
├── .env.example                       # documented env vars
├── .claude/settings.json              # Claude Code permissions
├── .codecov.yml
├── .docz.yaml
├── .github/
│   ├── labeler.yml
│   ├── CODEOWNERS
│   ├── actionlint.yml
│   └── workflows/
│       ├── ci.yml                     # single check job (typecheck + lint + format + test + build)
│       ├── release.yml                # docker build + push on tag
│       ├── pr-labels.yml
│       ├── trufflehog.yml
│       └── codeql.yml
├── src/
│   └── .gitkeep                       # placeholder
└── tests/
    └── setup.ts                       # vitest setup, imported by bunfig + vitest.config
```

### blueprint.hcl changes

Current `bun/std/blueprint.hcl` only has `project_name` + `license`.
Bring it in line with the other blueprints + add bun-specific bits:

```hcl
name        = "bun-std"
description = "Bun + TypeScript SSR webapp blueprint (React 19 + RR7 + Vite + Vitest + ESLint)"
version     = "0.2.0"
tags        = ["bun", "typescript", "react", "ssr"]

variable "project_name" {
  description = "Name of the project (lowercase, kebab-case)"
  type        = "string"
  required    = true
  validate    = "^[a-z][a-z0-9-]*$"
}

variable "project_owner" {
  description = "Owner of the project (user or org)"
  type        = "string"
  required    = true
  validate    = "^[a-z][a-z0-9-]*$"
}

variable "project_description" {
  description = "One-line description of the project"
  type        = "string"
  required    = true
}

variable "license" {
  description = "License type"
  type        = "choice"
  choices     = ["MIT", "Apache-2.0", "BSD-3-Clause", "UNLICENSED", "none"]
  default     = "MIT"
}

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
  description = "Org/user owning the repo"
  type        = "string"
  default     = "${project_owner}"
}

variable "bun_version" {
  description = "Bun version (matches mise.toml)"
  type        = "string"
  default     = "latest"
}

variable "node_version" {
  description = "Node version (kept for tool compat — eslint plugins, vitest)"
  type        = "string"
  default     = "22"
}

hooks {
  post_create = ["git init", "bun install"]
}

# No rename block — flatten pattern from PR #11.
```

Drop the `rename { ... }` block currently in `bun/std/blueprint.hcl`.

### Inheritance strategy

Same three-tier rule used everywhere else in the registry:

1. **Registry root `_defaults/`** — universal config (markdown,
   yaml, prettier, gitignore basics).
2. **`bun/_defaults/`** — Bun/TS-specific config (justfile shape,
   bunfig, mise, renovate, CI workflows, CLAUDE.md, catalog-info).
3. **`bun/std/`** — the actual webapp skeleton (package.json,
   tsconfig, vite/vitest configs, eslint config, Dockerfile,
   docker-bake, docker-compose, docker.just, src/, tests/).

Move out of `bun/_defaults/` (rely on registry-root inheritance):

- `.markdownlint.yaml`
- `.yamllint.yml`
- `.yamlfmt.yml`

Keep `.prettierrc.json` in `bun/_defaults/` because Bun/TS projects
want a different shape than the generic registry-root one (which is
`.prettierrc.yaml` markdown-focused). Drop `.prettierrc.yaml` from
`bun/_defaults/` so it doesn't shadow.

### Renovate annotations

`bun/_defaults/mise.toml` (to be rewritten) keeps every tool that
isn't `bun` itself annotated with a `# renovate: datasource=…` line
above so the custom regex manager in `donaldgifford/renovate-config`
picks them up. `bun` is `latest`-pinned and updated separately by
the Bun release manager.

Example shape:

```toml
[tools]
bun  = "${bun_version}"   # bumped via Renovate Bun manager
node = "${node_version}"  # LTS pin; bump via Renovate node manager

# Repo utilities
# renovate: datasource=github-releases depName=casey/just
just = "latest"
# renovate: datasource=github-releases depName=rhysd/actionlint
actionlint = "latest"

# Formatters / linters
# renovate: datasource=github-releases depName=DavidAnson/markdownlint-cli2
markdownlint-cli2 = "0.18.1"
# renovate: datasource=github-releases depName=google/yamlfmt
yamlfmt = "0.20.0"
# renovate: datasource=github-tags depName=adrienverge/yamllint
yamllint = "1.37.1"
# renovate: datasource=npm depName=prettier
prettier = "3.7.4"
```

Bun ecosystem deps (eslint, vitest, react, react-router, prettier
plugins) flow through the npm manager via `package.json` — Renovate
groups them per the shared `renovate-config:node` preset. No
per-line annotations needed.

`docker-bake.hcl.tmpl` and `Dockerfile.tmpl` use base images that
Renovate's Docker manager picks up by default (`node:20-alpine`,
`caddy:2-alpine`, etc.). No annotation needed.

## API / Interface Changes

User-facing changes when running `forge create bun/std my-app`:

- New required prompts (matching the Go blueprints' shape):
  `project_name`, `project_owner`, `project_description`.
- New optional prompts with defaults: `license` (MIT),
  `git_provider` (github), `git_host`, `project_org`, `bun_version`,
  `node_version`.
- Post-create hook runs `git init` + `bun install` — first
  `bun.lock` is generated automatically.
- Scaffolded project supports immediately: `just dev` (Vite dev
  server), `just test` (Vitest), `just lint`, `just format`,
  `just docker-build` (single-arch local), `just docker-buildx`
  (multi-arch).

Blueprint version: `0.1.0` → `0.2.0` (broad rewrite + new variables
= treat as additive minor, not breaking, since no existing
scaffolded projects depend on the blueprint shape).

## Testing Strategy

1. `forge create bun/std test-app --defaults` succeeds; post-create
   `bun install` resolves with no errors and produces `bun.lock`.
2. Rendered tree matches the
   [File inventory](#file-inventory-after-alignment).
3. `cd test-app && bun run dev` brings up Vite without errors;
   navigate to localhost and confirm SSR renders the placeholder
   page.
4. `bun run test`, `bun run lint`, `bun run format:check`,
   `bun run typecheck` all pass on the empty scaffold.
5. `docker buildx bake --print` resolves; `docker buildx bake`
   completes for the dev target.
6. `docker compose --profile dev up` brings up the dev container
   (sanity check).
7. `actionlint .github/workflows/*.yml` passes.
8. `/registry-validate` reports clean.
9. Diff rendered `package.json` against rfc-site's and document
   intentional deviations.

## Migration / Rollout Plan

Additive — no existing `bun/std` scaffolds exist yet (the blueprint
is too new to have downstream consumers). Single PR:

1. Rewrite `bun/_defaults/justfile.tmpl`, `CLAUDE.md.tmpl`,
   `mise.toml`, `catalog-info.yaml.tmpl`.
2. Delete from `bun/_defaults/`: `.prettierrc.yaml`,
   `.markdownlint.yaml`, `.yamllint.yml`, `.yamlfmt.yml`,
   `.github/dependabot.yml`, `.github/licenses-csv.tpl`,
   `.github/workflows/{changelog,changelog-regen,license-check}.yml`.
3. Rewrite `bun/std/`: `blueprint.hcl`, `package.json.tmpl`,
   `Dockerfile.tmpl`, `docker-compose.yml.tmpl`, `vitest.config.ts`,
   `eslint.config.js`, `justfile.docker.tmpl` → `docker.just.tmpl`.
4. Delete from `bun/std/`: `charts/`, `ct.yaml`, `orval.config.ts`
   (rfc-site-specific tooling), `react-router.config.ts` moves to
   `_defaults` if it's a universal shape, else stays.
5. Add `src/.gitkeep` and `tests/setup.ts` placeholders.
6. Verify post-create scaffold passes the full Testing Strategy
   checklist.
7. Run `forge registry update` and `/registry-validate`.
8. Land in one PR. Bump `bun/std` to `0.2.0`.

## Open Questions

Each question lists my recommendation as **a.** with alternatives.

### 1. Cover the backstage-api shape (Bun server + Biome + bun test) as a sibling blueprint?

rfc-site and backstage-api are sufficiently different in toolchain
(ESLint+Prettier vs Biome, Vitest vs `bun test`, Vite vs native
`bun build`) that one blueprint can't cleanly serve both.

- **a.** Out of scope here. Land `bun/std` as the React SSR webapp
  shape. If the backstage-api shape is something we'll scaffold
  again, add `bun/api` (or `bun/server`) as a follow-up blueprint
  in a separate design. Recommended — keep this PR focused.
- **b.** Bundle both: create `bun/std` (React SSR) AND `bun/api`
  (Bun server) in this PR. More upfront work; less inheritance to
  share since the toolchains barely overlap.
- **c.** Single `bun/std` with a `kind` choice variable
  (`webapp` | `server`) that conditionally includes/excludes
  files. Likely too clever — diverges into two near-disjoint
  inheritance paths.

### 2. `.prettierrc.json` vs `.prettierrc.yaml` for bun?

Currently both exist in `bun/_defaults/`. Prettier resolves by file
order so this is ambiguous + non-deterministic.

- **a.** Keep `.prettierrc.json`, drop `.prettierrc.yaml`. rfc-site
  uses the JSON form. The YAML form at `bun/_defaults` is a
  leftover of the registry-root `.prettierrc.yaml` that lives at
  `_defaults/`. The Bun JSON shape includes per-file-type rules
  (`semi`, `singleQuote: false`, `trailingComma: all`, `printWidth:
  100`) that the markdown-focused YAML doesn't have. Recommended.
- **b.** Keep YAML, drop JSON. Inherit registry-root `_defaults/.prettierrc.yaml`
  and don't override at `bun/_defaults`. (Loses the JS/TS-tuned
  defaults.)
- **c.** Keep both with a precedence comment. Confusing — easy to
  edit the wrong one.

### 3. Keep cliff.toml + standalone changelog workflows for bun/std?

`bun/_defaults` carries `cliff.toml.tmpl`, `changelog.yml`,
`changelog-regen.yml`, `CHANGELOG.md` — copied from Go fleet.
rfc-site has none of these (no release process at all). Bun apps
that ship via `docker push` on tag don't need a textual changelog
in-repo.

- **a.** Drop all four from `bun/_defaults`. Bun/TS apps in
  practice rely on the Docker image tag + GitHub release notes
  (auto-generated by GitHub if you write conventional commits).
  Recommended — keeps the scaffold simple.
- **b.** Keep them — `CHANGELOG.md` is useful even without
  releases, and `git-cliff` is mise-pinned anyway.
- **c.** Keep `cliff.toml.tmpl` only; drop the workflows. Lets
  users run `git cliff` locally without the auto-regen overhead.

### 4. `package.json` dependency set — minimum viable React/RR7 or richer?

rfc-site's package.json includes 50+ deps (rehype/remark/shiki/
mermaid/orval/msw/jest-dom/etc.). The bare minimum to boot a RR7
SSR app is much smaller.

- **a.** Ship a minimal set: `react`, `react-dom`, `react-router`,
  `@react-router/{dev,node,serve,fs-routes}`, `vite`,
  `@vitejs/plugin-react`, `vitest`, `@vitest/coverage-v8`,
  `jsdom`, `@testing-library/{react,jest-dom,user-event}`,
  `typescript`, `eslint`, `typescript-eslint`, `eslint-plugin-react`,
  `eslint-plugin-react-hooks`, `eslint-plugin-jsx-a11y`,
  `eslint-config-prettier`, `prettier`, `@types/{node,react,react-dom}`.
  Document in CLAUDE.md how to add orval/msw/shiki if needed.
  Recommended — easier for users to evict deps they don't want.
- **b.** Match rfc-site's full set including orval/msw/shiki/mermaid.
  Heavier but "batteries included."
- **c.** Even more minimal — drop Testing Library, just ship Vitest
  + jsdom. Users add component test deps when they write component
  tests.

### 5. Dockerfile production stage — Caddy static or Bun SSR server?

Current `bun/std/Dockerfile` builds with Bun, then serves static
files from `dist/` via Caddy. That's appropriate for client-rendered
React, but RR7 SSR needs a Node/Bun server runtime — Vite emits a
`build/server/index.js` that's run via `react-router-serve`.

- **a.** Two-stage prod: builder runs `bun run build`, runtime
  stage runs `bunx react-router-serve ./build/server/index.js` on
  a slim `oven/bun:1-alpine`. Drop Caddy. This matches RR7 SSR
  semantics and what `package.json scripts.start` does locally.
  Recommended.
- **b.** Keep Caddy + static — assumes client-only SPA. Faster, no
  Node runtime in prod, but loses SSR.
- **c.** Ship both, gated by a `render_mode` blueprint variable
  (`ssr` | `spa`). Probably premature.

### 6. CI workflow set — slim rfc-site shape or richer Go-fleet shape?

`bun/_defaults/.github/workflows/` has 11 workflows copied from the
Go fleet. rfc-site has 1 (`ci.yml` with a single `check` job).

- **a.** Slim to: `ci.yml` (rfc-site single-check shape),
  `release.yml` (docker build+push on tag),
  `pr-labels.yml`, `trufflehog.yml`, `codeql.yml`. Drop:
  `changelog.yml`, `changelog-regen.yml`, `license-check.yml`,
  `dependabot-severity-label.yml`, `dependabot.yml`,
  `security.yml` (folded into codeql), `actionlint.yml`
  (fold actionlint into `ci.yml` as a step).
  Recommended — matches the rfc-site reference shape.
- **b.** Keep the full Go-fleet shape — defense in depth.
- **c.** Strictly mirror rfc-site = just `ci.yml`. No codeql/
  trufflehog. Too minimal IMO — those run cheap and catch real
  issues.

### 7. `react-router.config.ts` lives in `bun/std` or `bun/_defaults`?

This config is universal to any RR7 SSR app (currently identical
across rfc-site and the rough bun/std scaffold). But it's React-
specific, not general Bun/TS.

- **a.** Keep in `bun/std/`. If a future `bun/api` or `bun/cli`
  blueprint lands, they don't need RR7. Recommended — keeps
  `bun/_defaults` agnostic to which TS app shape lives downstream.
- **b.** Move to `bun/_defaults/`. Sharing if future React-flavored
  bun blueprints want it; harmless extra file if not.

### 8. `git_provider` default for `bun/std` — github or forgejo?

Same question as DESIGN-0002 Open Question 7. rfc-site and
backstage-api are both GitHub-hosted, no Forgejo presence.

- **a.** Default `github`. rfc-site and backstage-api both live
  there. Recommended.
- **b.** Default `forgejo` — match `homelab/go`'s default.
- **c.** Required (no default).

### 9. Should bun/std emit `tests/setup.ts` with content, or just `.gitkeep`?

`bunfig.toml` and `vitest.config.ts` both reference
`./tests/setup.ts` as a preload. If it doesn't exist, both tools
warn or error.

- **a.** Ship a real `tests/setup.ts.tmpl` with `import
  "@testing-library/jest-dom/vitest"` and a placeholder comment
  explaining what it's for. Recommended — runnable out of the
  box.
- **b.** Ship `tests/setup.ts` as just `.gitkeep` and let the
  user write it. They'll see the runtime error and figure it out.
- **c.** Drop the preload from `bunfig.toml`+`vitest.config.ts`
  defaults entirely; users add it if they want it.

### 10. `docker.just` filename + import path

The current file is `bun/std/justfile.docker.tmpl`. The justfile
imports it as `import 'docker.just'`. The Go pattern uses
`docker.just.tmpl` so the rendered file is literally `docker.just`.

- **a.** Rename to `docker.just.tmpl` to match the Go pattern and
  the import. Recommended.
- **b.** Keep as `justfile.docker.tmpl` and change the justfile
  import to `import 'justfile.docker'`.

## References

- [DESIGN-0002](./0002-align-gostd-blueprint-with-hclkit-conventions.md) —
  the parallel go/std alignment design
- [donaldgifford/rfc-site](https://github.com/donaldgifford/rfc-site) —
  canonical reference for the React+RR7+Vite+Vitest+ESLint+Prettier
  shape (this design's chosen flavor)
- [donaldgifford/backstage-api](https://github.com/donaldgifford/backstage-api) —
  alternative reference (Bun server + Biome + `bun test`) deferred
  to a future sibling blueprint
- [donaldgifford/renovate-config](https://github.com/donaldgifford/renovate-config) —
  shared Renovate extends consumed via `:node` `:docker` `:mise` `:ci`
  presets
- `go/docker/docker.just.tmpl` — pattern this design's
  `bun/std/docker.just.tmpl` mirrors
- `go/_defaults/justfile.tmpl` — structural reference for the
  rewrite of `bun/_defaults/justfile.tmpl` (recipe groups, set
  shell, etc. — content is bun-specific)
