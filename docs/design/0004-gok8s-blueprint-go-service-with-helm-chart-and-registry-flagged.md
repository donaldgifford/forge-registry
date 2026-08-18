---
id: DESIGN-0004
title: "go/k8s Blueprint: Go Service with Helm Chart and Registry-Flagged CI"
status: Draft
author: Donald Gifford
created: 2026-08-15
---
<!-- markdownlint-disable-file MD025 MD041 -->

# DESIGN 0004: go/k8s Blueprint: Go Service with Helm Chart and Registry-Flagged CI

**Status:** Draft
**Author:** Donald Gifford
**Date:** 2026-08-15

<!--toc:start-->
- [Overview](#overview)
- [Goals and Non-Goals](#goals-and-non-goals)
  - [Goals](#goals)
  - [Non-Goals](#non-goals)
- [Background](#background)
  - [Reference: repo-guardian](#reference-repo-guardian)
  - [Current go/k8s seeded state](#current-gok8s-seeded-state)
  - [Defects in the seeded state](#defects-in-the-seeded-state)
- [Detailed Design](#detailed-design)
  - [Feature-flag surface](#feature-flag-surface)
  - [File inventory after templating](#file-inventory-after-templating)
  - [blueprint.hcl](#blueprinthcl)
  - [Chart templating strategy](#chart-templating-strategy)
  - [CI strategy](#ci-strategy)
  - [Task runner](#task-runner)
- [API / Interface Changes](#api--interface-changes)
- [Testing Strategy](#testing-strategy)
- [Migration / Rollout Plan](#migration--rollout-plan)
- [Open Questions](#open-questions)
  - [1. Blueprint-time flags vs chart-values toggles for monitoring?](#1-blueprint-time-flags-vs-chart-values-toggles-for-monitoring)
  - [2. Drop repo-guardian's backend templates (valkey/postgres/cnpg/tailscale) entirely?](#2-drop-repo-guardians-backend-templates-valkeypostgrescnpgtailscale-entirely)
  - [3. Keep the PrometheusRule starter alert pack?](#3-keep-the-prometheusrule-starter-alert-pack)
  - [4. Makefile in go/k8s?](#4-makefile-in-gok8s)
  - [5. Where does the ECR operator-prep doc live?](#5-where-does-the-ecr-operator-prep-doc-live)
  - [6. Keep gh-pages.yml (mkdocs docs site)?](#6-keep-gh-pagesyml-mkdocs-docs-site)
  - [7. Local kind-based chart install testing (ct install)?](#7-local-kind-based-chart-install-testing-ct-install)
  - [8. Keep ghcr.yml/ecr.yml as reusable (workflow_call) workflows or inline into release.yml?](#8-keep-ghcrymlecryml-as-reusable-workflowcall-workflows-or-inline-into-releaseyml)
  - [9. Chart-scoped changelog (chart cliff.toml + CHANGELOG.md)?](#9-chart-scoped-changelog-chart-clifftoml--changelogmd)
- [References](#references)
<!--toc:end-->

## Overview

`go/k8s` is a new blueprint for a Go service that ships as a container
image (like `go/docker`) **plus** a templated Helm chart, with CI baked
in for helm testing (helm-unittest, chart-testing, helm-docs) and
publish workflows that push both the image and the chart to either
GHCR or ECR based on variables chosen at `forge create` time.

The seeded files are lifted from `donaldgifford/repo-guardian` (a
GitHub App with a production-hardened chart + release train). This
design maps what gets templated, what gets feature-flagged, what gets
dropped as repo-guardian-specific, and where the registry choice
(ghcr/ecr) plugs into blueprint `condition` blocks.

## Goals and Non-Goals

### Goals

- `forge create go/k8s my-svc` produces a Go service scaffold with:
  - Multi-stage distroless `Dockerfile` + `docker-bake.hcl` +
    `docker.just` (same pipeline as `go/docker`).
  - A working Helm chart at `charts/my-svc/` that lints
    (`helm lint`, `ct lint`), unit-tests (`helm-unittest`), and
    renders (`helm template`) out of the box.
  - CI wired for both Go (lint/test/build) and chart
    (helm-unittest, ct) validation on every PR.
  - A release train: PR label → semver bump → image + chart publish
    to the chosen registry (GHCR or ECR), including SLSA provenance
    jobs as seeded from repo-guardian.
- Registry choice is a blueprint variable; only the matching publish
  workflow ships (condition blocks exclude the other).
- Chart extras (ServiceMonitor, PrometheusRule) are chart-values
  toggles that default off but ship in the chart, mirroring
  repo-guardian's pattern.
- Everything hardcoded to `repo-guardian` / `donaldgifford` is
  templated to `${project_name}` / `${project_owner}`.

### Non-Goals

- Reproducing repo-guardian's app-specific backends — the valkey
  queue, postgres/CNPG store, tailscale sidecar, and policy
  configmap templates are repo-guardian domain logic, not generic
  service scaffolding. Dropped (see
  [Open Question 2](#open-questions)).
- The monitoring-drift/`contrib/generated` alert-tier machinery from
  repo-guardian's Makefile and `lint-alerts`/`monitoring-drift` CI
  jobs — app-specific, dropped (Open Question 3 covers what remains).
- A `gh-pages`/mkdocs docs site — seeded `gh-pages.yml` is
  repo-guardian's docs pipeline (see [Open Question 6](#open-questions)).
- kubebuilder-style operators — `go/kubebuilder` already covers that.
- Aligning this blueprint with the DESIGN-0002 (hclkit) decisions —
  whatever lands there for `go/_defaults` will be inherited here
  automatically; this design only defines what's `go/k8s`-specific.

## Background

### Reference: repo-guardian

repo-guardian's relevant shape (what we're generalizing):

- Go service in `cmd/` + `internal/`, distroless multi-arch image
  via docker-bake (default / ci / release groups).
- Helm chart under `charts/repo-guardian/` with:
  - helm-unittest suite in `tests/` (11 test files).
  - `values.schema.json` for values validation.
  - helm-docs (`README.md.gotmpl`) for generated chart docs.
  - `ci/ci-values.yaml` for chart-testing installs.
  - Per-chart `cliff.toml` + `CHANGELOG.md` (chart-scoped changelog
    via `--include-path 'charts/**'`).
  - Optional ServiceMonitor/PrometheusRule gated on
    `.Values.serviceMonitor.enabled` / `.Values.prometheusRule.enabled`.
  - App-specific optional backends (valkey queue, postgres store in
    baked/cnpg modes, tailscale) gated on values.
- CI (`ci.yml`): changes-detection → lint, test-go, security, build,
  docker-build, helm-unittest, helm-test (+ repo-guardian-specific
  lint-alerts, monitoring-drift).
- Release (`release.yml`): `pr-semver-bump` on merge to main reads
  major/minor/patch labels → tags → calls `ghcr.yml` / `ecr.yml` as
  reusable workflows (`workflow_call`) with the new tag.
- Publish workflows (`ghcr.yml`, `ecr.yml`): image job (bake +
  digest capture + SLSA provenance) and chart job (helm package +
  push to OCI registry, idempotent via `helm pull` precheck). ECR
  variant adds an OIDC/aws-auth job and expects
  `ECR_AWS_ACCOUNT_ID` / `ECR_REGION` / `ECR_ROLE_ARN` secrets.

### Current go/k8s seeded state

Seeded on branch `feat/go-k8s` (untracked). Inventory:

| Area | Files | State |
|---|---|---|
| Blueprint | `blueprint.hcl` | forge-init starter — only `project_name` + `license`, still has the `${project_name}/` rename block (pattern removed registry-wide in PR #11) |
| Docker | `Dockerfile.tmpl`, `docker-bake.hcl.tmpl`, `docker.just.tmpl`, `.dockerignore` | Templated, matches `go/docker` |
| Chart | `charts/${project_name}/**` (33 files) | Mixed: `Chart.yaml.tmpl` + `values.yaml.tmpl` templated; **all** `templates/*.yaml`, `tests/*.yaml`, `_helpers.tpl`, `values.schema.json`, `README.md*` still hardcode `repo-guardian` |
| Helm tooling | `ct.yaml`, `charts/.yamllint.yml.tmpl`, `helm.just` | Present; helm.just has defects (below) |
| CI | `.github/workflows/{ci,release,ghcr,ecr,security,license-check,pr-labels,changelog-update,gh-pages}.yml`, `labeler.yml` | Hardcode `repo-guardian` / `donaldgifford`; include repo-guardian-specific jobs |
| Repo config | `mise.toml` **and** `mise.toml.tmpl`, `Makefile`, `README.md.tmpl`, `renovate.json5.tmpl`, `cliff.toml.tmpl`, `CHANGELOG.md`, `.gitignore` | mise duplicated (raw copy + template); Makefile is repo-guardian's verbatim |

### Defects in the seeded state

1. **`values.yaml.tmpl` / templates mismatch** — the values file has
   been scrubbed of `queue:`, `store:`, `tailscale:`, `policy:`
   sections, but the chart still ships
   `queue-valkey*.yaml`, `store-postgres*.yaml`, `store-cnpg-*.yaml`,
   `tailscale-*.yaml`, `policy-configmap.yaml` templates referencing
   `.Values.queue.backend` etc. Rendering nil-pointers immediately.
   The corresponding `tests/backend_shapes_test.yaml`,
   `tests/policy_test.yaml`, `tests/deployment_env_test.yaml` also
   exercise those backends.
2. **`_helpers.tpl` + every template hardcodes `repo-guardian`**
   (29 occurrences in helpers alone: `repo-guardian.fullname`,
   `repo-guardian.labels`, validation helpers, etc.).
3. **`helm.just` is a Makefile/justfile hybrid** — recipes contain
   `@ $(MAKE) --no-print-directory log-$@` lines (Makefile idiom,
   breaks under just), `## comment` suffixes (Makefile
   self-documentation convention; just uses `# comment` above the
   recipe), and references an undefined `{{ project_name }}` just
   variable. `helm-template` hardcodes repo-guardian's
   `--set config.appId/webhookSecret/privateKey` flags. `helm-push`
   pushes to `oci://charts` (placeholder). Needs a rewrite.
4. **Both `mise.toml` and `mise.toml.tmpl` exist** — raw copy from
   repo-guardian plus the started template. Both would land in
   scaffold output; the raw one must go.
5. **`Makefile` is repo-guardian's verbatim** — PROJECT_NAME,
   monitoring-drift machinery, chart-alerts rendering. Either
   template or drop (Open Question 4).
6. **`ct.yaml` schema line is wrong** — points at
   `helm-testsuite.json` (helm-unittest's schema, not
   chart-testing's; same fix already applied to `bun/std/ct.yaml`).
7. **`blueprint.hcl` rename block** — `${project_name}/` → `.` wrapper
   pattern that PR #11 removed registry-wide. There is no top-level
   `${project_name}/` wrapper here (the chart nesting under
   `charts/${project_name}/` is intentional and stays), so the
   rename block is dead config. Drop it.
8. **`charts/.yamllint.yml.tmpl` references `${chart_name}`** — an
   undeclared variable (blueprint only declares `project_name`,
   `license`). Should be `${project_name}`.
9. **Workflows carry repo-guardian coupling**: `ci.yml` has
   `lint-alerts` + `monitoring-drift` jobs (drop), `ghcr.yml` env
   block hardcodes `IMAGE_REPO: donaldgifford/repo-guardian` +
   `CHART_NAMESPACE: donaldgifford/charts`, `ecr.yml` hardcodes
   `IMAGE_NAME`/`CHART_NAME`/`CHART_REPO`.

## Detailed Design

### Feature-flag surface

Two kinds of flags, kept deliberately distinct:

**Blueprint-time flags** (forge variables + `condition` blocks —
decide what files exist in the scaffold):

| Variable | Type | Effect |
|---|---|---|
| `container_registry` | string (validation: `ghcr` \| `ecr`) | Ships `release-ghcr.yml` XOR `release-ecr.yml` (self-contained release trains — Q8 decision); sets image repo refs in `values.yaml`, `docker-bake.hcl`, chart docs |
| `enable_monitoring` | bool (default true) | Ships `servicemonitor.yaml` + `prometheusrule.yaml` + their tests; excluded entirely when off |
| `enable_helm_docs` | bool (default true) | Ships `README.md.gotmpl` + helm-docs recipe/CI step |

**Chart-values toggles** (runtime, ship always when the files exist,
default off — the repo-guardian pattern): `serviceMonitor.enabled`,
`prometheusRule.enabled`. When `enable_monitoring` is on, the
templates ship but stay disabled until the operator flips the value
at install time.

Rationale: registry choice changes secrets, OIDC setup, and workflow
plumbing — structural, so it's a blueprint flag. Monitoring is cheap
to carry in the chart and the k8s convention is install-time opt-in
via values; the blueprint flag only controls whether the files exist
at all for teams that will never run Prometheus.

### File inventory after templating

```text
my-svc/
├── cmd/my-svc/main.go                 # from go/_defaults (inherited)
├── Dockerfile                         # ✔ seeded, templated
├── docker-bake.hcl                    # ✔ seeded, templated
├── docker.just                        # ✔ seeded, templated
├── helm.just                          # REWRITE (defect 3)
├── justfile                           # from go/_defaults; imports docker.just + helm.just
├── ct.yaml                            # fix schema line
├── mise.toml                          # from mise.toml.tmpl only (drop raw copy)
├── cliff.toml                         # root changelog
├── renovate.json5                     # ✔ seeded
├── README.md                          # ✔ seeded, templated
├── .gitignore / .dockerignore         # ✔ seeded
├── charts/
│   ├── .yamllint.yml                  # fix ${chart_name} → ${project_name}
│   └── my-svc/
│       ├── Chart.yaml                 # ✔ templated
│       ├── values.yaml                # ✔ templated (post-scrub shape)
│       ├── values.schema.json         # TEMPLATE + strip backend defs
│       ├── .helmignore                # ✔
│       ├── ci/ci-values.yaml          # scrub repo-guardian secrets
│       ├── cliff.toml                 # chart-scoped changelog
│       ├── CHANGELOG.md               # seed empty
│       ├── README.md.gotmpl           # helm-docs source (flag: enable_helm_docs)
│       ├── templates/
│       │   ├── _helpers.tpl           # TEMPLATE all repo-guardian.* helper names
│       │   ├── deployment.yaml        # TEMPLATE includes; strip backend env wiring
│       │   ├── service.yaml           # TEMPLATE
│       │   ├── serviceaccount.yaml    # TEMPLATE
│       │   ├── configmap.yaml         # TEMPLATE, generalize to app config
│       │   ├── secret.yaml            # TEMPLATE, generalize
│       │   ├── NOTES.txt              # TEMPLATE
│       │   ├── servicemonitor.yaml    # TEMPLATE (flag: enable_monitoring)
│       │   └── prometheusrule.yaml    # TEMPLATE + strip app alerts (flag)
│       └── tests/
│           ├── deployment_test.yaml   # TEMPLATE
│           ├── service_test.yaml      # TEMPLATE
│           ├── serviceaccount_test.yaml
│           ├── configmap_test.yaml
│           ├── secret_test.yaml
│           ├── servicemonitor_test.yaml   # (flag: enable_monitoring)
│           ├── prometheusrule_test.yaml   # (flag: enable_monitoring)
│           └── values_guard_test.yaml
└── .github/
    ├── labeler.yml                    # scrub repo-guardian paths
    └── workflows/
        ├── ci.yml                     # drop lint-alerts + monitoring-drift jobs
        ├── release.yml                # rendered from release-ghcr.yml.tmpl XOR
        │                              # release-ecr.yml.tmpl (Q8: self-contained
        │                              # per-registry release trains)
        ├── security.yml               # ✔
        ├── license-check.yml          # ✔
        ├── pr-labels.yml              # ✔
        └── changelog-update.yml       # keep (chart+root cliff regen)
```

Dropped from the seed: `queue-valkey*.yaml`, `store-postgres*.yaml`,
`store-cnpg-*.yaml`, `tailscale-*.yaml`, `policy-configmap.yaml`,
`tests/backend_shapes_test.yaml`, `tests/policy_test.yaml`,
`tests/deployment_env_test.yaml` (backend-coupled),
`charts/${project_name}/docs/publishing-to-ecr.md` (relocated — Open
Question 5), `Makefile` + raw `mise.toml`,
`charts/${project_name}/README.md` (generated artifact; the gotmpl
is the source), `gh-pages.yml` (Open Question 6).

### blueprint.hcl

```hcl
name        = "go-k8s"
description = "Go service with container image + Helm chart, registry-flagged CI (GHCR/ECR)"
version     = "0.1.0"
tags        = ["go", "k8s", "helm", "docker"]

# forge v0.8 variable syntax (IMPL-0009): bareword types +
# `validation` blocks. The legacy choice/choices/validate forms
# are rejected at load time from v0.8 on.

variable "project_name" {
  description = "Name of the project (lowercase, kebab-case)"
  type        = string
  required    = true
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "project_name must be lowercase kebab-case."
  }
}

variable "project_owner" {
  description = "Owner of the project (user or org)"
  type        = string
  required    = true
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_owner))
    error_message = "project_owner must be lowercase kebab-case."
  }
}

variable "project_description" {
  description = "One-line description of the project"
  type        = string
  required    = true
}

variable "license" {
  description = "License type"
  type        = string
  default     = "Apache-2.0"
  validation {
    condition     = contains(["MIT", "Apache-2.0", "BSD-3-Clause", "none"], var.license)
    error_message = "license must be one of: MIT, Apache-2.0, BSD-3-Clause, none."
  }
}

variable "go_version" {
  description = "Go toolchain version (matches go.mod + mise.toml + Dockerfile)"
  type        = string
  default     = "1.26"
}

variable "container_registry" {
  description = "Where CI publishes the image + chart"
  type        = string
  default     = "ghcr"
  validation {
    condition     = contains(["ghcr", "ecr"], var.container_registry)
    error_message = "container_registry must be one of: ghcr, ecr."
  }
}

variable "enable_monitoring" {
  description = "Ship ServiceMonitor + PrometheusRule chart templates (values-gated at runtime)"
  type        = bool
  default     = true
}

variable "enable_helm_docs" {
  description = "Ship helm-docs README.md.gotmpl + docs generation recipe/CI"
  type        = bool
  default     = true
}

condition {
  when    = container_registry != "ghcr"
  exclude = [".github/workflows/release-ghcr.yml"]
}

condition {
  when    = container_registry != "ecr"
  exclude = [".github/workflows/release-ecr.yml"]
}

rename {
  entry {
    from = ".github/workflows/release-${container_registry}.yml"
    to   = ".github/workflows/release.yml"
  }
}

condition {
  when    = !enable_monitoring
  exclude = [
    "charts/$${project_name}/templates/servicemonitor.yaml.tmpl",
    "charts/$${project_name}/templates/prometheusrule.yaml.tmpl",
    "charts/$${project_name}/tests/servicemonitor_test.yaml.tmpl",
    "charts/$${project_name}/tests/prometheusrule_test.yaml.tmpl",
  ]
}

condition {
  when    = !enable_helm_docs
  exclude = ["charts/$${project_name}/README.md.gotmpl.tmpl"]
}

hooks {
  post_create = ["git init", "go mod tidy"]
}
```

Notes:

- **Targets forge v0.8** (IMPL-0009 variable-type overhaul; see
  registry issue #14). v0.8 removes `type = "choice"`, `choices`,
  and the legacy `validate` regex attribute — enums become
  `validation { contains(...) }` blocks, regexes become
  `can(regex(...))`. The installed v0.7 binary cannot load this
  blueprint; bump forge to v0.8 before implementing. The rest of
  the registry migrates separately (issue #14) — go/k8s just lands
  on v0.8 first.
- Verified against forge source (IMPL-0002 records file/line
  refs): `exclude` entries are evaluated with a nil context at
  blueprint-load time, so forge variables cannot interpolate there.
  `$${project_name}` emits the literal `${project_name}`, which
  exactly matches the literal source directory name; patterns match
  source paths, `.tmpl` extension included.
- Verified: `rename.from` interpolates variables and prefix-matches
  the rendered path before the `.tmpl` strip; an entry matching no
  file (the condition-excluded release variant) is a no-op, so the
  single rename entry above is safe as written (Q8 decision: the
  blueprint ships both self-contained release trains; conditions
  exclude the non-selected one and the rename normalizes the
  winner's filename).

### Chart templating strategy

The chart has two template layers that must not collide:

- **forge variables** — `${project_name}`, `${project_owner}`:
  HCL2, resolved once at scaffold time.
- **Helm/Go template syntax** — `{{ include "..." . }}`: passes
  through HCL2 untouched (PR #10 established this; no escaping
  needed for `{{ }}`).
- **Shell-style `${...}` strings** inside NOTES.txt or workflow run
  blocks need `$${...}` so HCL2 emits a literal for the downstream
  consumer.

Concretely: `_helpers.tpl`'s `repo-guardian.fullname` etc. become
`${project_name}.fullname`, rendering to `my-svc.fullname` — exactly
Helm's per-chart helper naming convention. Every chart file that
gains a forge variable also gains the `.tmpl` extension
(`_helpers.tpl` → `_helpers.tpl.tmpl`, `deployment.yaml` →
`deployment.yaml.tmpl`, …); forge strips it on output, restoring the
Helm-expected filenames. Files with no forge variables (e.g.
`.helmignore`) stay extension-less and copy verbatim.

`values.schema.json` gets `.tmpl` (image repo default embeds
owner/name) and loses the `queue`/`store`/`tailscale`/`policy`
property definitions — the schema half of defect 1.

`deployment.yaml` gets the backend env wiring stripped
(`validateBackendSecrets` include, queue/store env blocks) so it
renders cleanly against the scrubbed values.

The `repo-guardian.validateTemplatingVars` /
`validateRemovedValues` guard helpers are a nice pattern worth
keeping — they fail fast at `helm template` time when required
values are missing or when the operator sets values that were
removed in a chart upgrade. Rename to `${project_name}.*` and prune
their rule lists down to the generic values that survive the scrub.

### CI strategy

- `ci.yml`: keep changes-detection, labeler, lint, test-go,
  security, build, docker-build, helm-unittest, helm-test. Drop
  `lint-alerts` + `monitoring-drift`. Helm jobs stay gated on
  `charts/**` changes via the seeded changes-filter.
- **Per-registry release trains (Q8 decision)**: the seeded
  release.yml + ghcr.yml/ecr.yml `workflow_call` indirection is
  collapsed. The blueprint ships two complete release workflow
  templates — `release-ghcr.yml.tmpl` and `release-ecr.yml.tmpl` —
  each containing the full train: pr-semver-bump job
  (major/minor/patch/dont-release labels, covered by
  `scripts/labels.sh`) followed by the registry's image + chart
  publish jobs (SLSA provenance jobs kept as seeded; ECR variant
  keeps its aws-auth OIDC job + operator-prep comments). Condition
  blocks exclude the non-selected variant and the survivor renders
  as `.github/workflows/release.yml`. Each keeps a
  `workflow_dispatch` trigger with `tag` + `dry_run` inputs so
  ad-hoc republish still works without the reusable-workflow split.
  Adding a future registry (e.g. Harbor) = one new
  `release-<registry>.yml.tmpl` + one condition entry + one choice
  value.
- Registry-specific env templating:
  ghcr — `IMAGE_REPO: ${project_owner}/${project_name}`,
  `CHART_NAMESPACE: ${project_owner}/charts`,
  `CHART_NAME: ${project_name}`;
  ecr — `IMAGE_NAME` / `CHART_NAME` / `CHART_REPO` equivalents.
- `changelog-update.yml`: keep — regenerates root + chart
  changelogs from the two cliff configs.

### Task runner

`helm.just` rewritten as a clean just module, imported from the main
justfile alongside `docker.just`:

```just
# ${project_name} — helm recipes

chart_root := "charts"
chart_dir  := chart_root + "/${project_name}"

# Lint chart (helm lint + ct lint)
[group('helm')]
helm-lint:
    @helm lint {{ chart_dir }}
    @ct lint --config ct.yaml --all

# Render templates with default values
[group('helm')]
helm-template:
    @helm template ${project_name} {{ chart_dir }}

# Render with CI values
[group('helm')]
helm-template-ci:
    @helm template ${project_name} {{ chart_dir }} -f {{ chart_dir }}/ci/ci-values.yaml

# Run helm-unittest suite
[group('helm')]
helm-unittest:
    @helm unittest {{ chart_dir }}

# Full chart gate: lint + unittest
[group('helm')]
helm-test: helm-lint helm-unittest

# Generate chart README via helm-docs
[group('helm')]
helm-docs:
    @helm-docs --chart-search-root {{ chart_root }}

# Package + push chart to the configured OCI registry
[group('helm')]
helm-push:
    @helm package {{ chart_dir }}
    @helm push ${project_name}-*.tgz oci://ghcr.io/${project_owner}/charts

# ─── Local cluster (k3d) ────────────────────────────────────────────

# Create a local k3d cluster for chart testing
[group('k3d')]
k3d-up:
    @k3d cluster create ${project_name} --wait

# Delete the local k3d cluster
[group('k3d')]
k3d-down:
    @k3d cluster delete ${project_name}

# Build the image, import it into k3d, install the chart
[group('k3d')]
k3d-install: 
    @docker buildx bake
    @k3d image import ghcr.io/${project_owner}/${project_name}:dev -c ${project_name}
    @helm upgrade --install ${project_name} {{ chart_dir }} \
        -f {{ chart_dir }}/ci/ci-values.yaml \
        --set image.tag=dev --set image.pullPolicy=Never

# Uninstall the chart from the k3d cluster
[group('k3d')]
k3d-uninstall:
    @helm uninstall ${project_name}
```

(`helm-push`'s registry ref templated per `container_registry`.
The `{{ chart_dir }}` braces are just-variables — they pass through
HCL2 and resolve at just runtime; `${project_name}` resolves at
scaffold time. Same two-layer pattern as the chart.)

Local testing decision (Q7 rider): repo-guardian tests locally with
docker compose, but compose can only run the raw container — it
can't exercise the chart (helpers, values wiring, probes, RBAC).
k3d (k3s-in-docker) gives a real Kubernetes API with near-kind
startup speed, so the local loop becomes: `just k3d-up` →
`just k3d-install` → iterate → `just k3d-down`. `k3d` gets added
to `mise.toml.tmpl` (renovate-annotated), and no docker-compose.yml
ships in this blueprint.

**CI stays on kind deliberately** — repo-guardian evaluated k3d for
the CI helm-testing path and kept kind because k3d lacked a
capability the helm test flow needed (kind + helm/kind-action +
`ct install` is also the chart-testing ecosystem's first-class
path). So the split is: kind in CI (proven, ct-native), k3d locally
(faster startup, better local DX). Re-evaluate only if the k3d gap
closes and there's a reason to converge.

The seeded `Makefile` is dropped (defect 5); `go/_defaults`
inheritance supplies justfile/Makefile per whatever DESIGN-0002
decides. The main justfile needs `import 'helm.just'` — since the
inherited `go/_defaults/justfile.tmpl` doesn't import it, `go/k8s`
overrides the justfile (or the import mechanism gets sorted in
DESIGN-0002's implementation — resolve at implementation time).

## API / Interface Changes

`forge create go/k8s my-svc` prompts:

- `project_name`, `project_owner`, `project_description` (required)
- `license` (default Apache-2.0), `go_version` (default 1.26)
- `container_registry` — **ghcr** | ecr
- `enable_monitoring` — default true
- `enable_helm_docs` — default true

Post-create hooks: `git init`, `go mod tidy`.

New `registry.hcl` entry via `forge registry update` (the branch
already has the entry pending — verify it after the blueprint.hcl
rewrite).

## Testing Strategy

1. `forge create go/k8s test-svc --defaults` scaffolds cleanly;
   hooks pass.
2. `helm lint charts/test-svc` and
   `helm template test-svc charts/test-svc` succeed with zero
   overrides (guards defect 1).
3. `helm unittest charts/test-svc` passes the templated suite.
4. `ct lint --config ct.yaml --all` passes.
5. `helm-docs` generates the chart README without error (when
   enabled).
6. `docker buildx bake --print` resolves.
7. `actionlint` passes on all rendered workflows.
8. Flag matrix:
   - `container_registry=ecr` → only `ecr.yml` ships; `release.yml`
     references it.
   - `enable_monitoring=false` → no servicemonitor/prometheusrule
     files; chart still lints + unit-tests clean.
   - `enable_helm_docs=false` → no gotmpl; CI has no helm-docs step.
9. `grep -r "repo-guardian\|donaldgifford/repo" <rendered>` → zero
   hits (scrub guard).
10. `/registry-validate` clean.

## Migration / Rollout Plan

Single PR on `feat/go-k8s`:

1. Rewrite `blueprint.hcl` (variables, conditions, drop rename
   block).
2. Delete repo-guardian-specific files (backend templates + their
   tests, monitoring machinery, raw `mise.toml`, `Makefile`,
   generated chart README, `gh-pages.yml` pending Open Question 6).
3. Template the chart — helpers, templates, tests, schema — adding
   `.tmpl` extensions where forge variables are introduced.
4. Rewrite `helm.just`; fix `ct.yaml` schema line; fix
   `charts/.yamllint.yml.tmpl` variable; sort the justfile import.
5. Template the workflows; drop repo-guardian jobs; template the
   `release.yml` → publish-workflow reference.
6. Run the full Testing Strategy matrix.
7. `forge registry update`; land as `go/k8s 0.1.0`.

## Open Questions

Each question lists my recommendation as **a.** with alternatives.

> **All questions resolved 2026-08-15.** Decisions: 1a, 2a, 3a, 4a,
> 5a, 6a, 7a (with k3d for local chart testing instead of
> repo-guardian's docker compose — see Task runner section), 8b
> (self-contained per-registry release workflows so the blueprint
> choice drives the whole release train and future registries are
> one file + one condition away), 9a. Design sections above have
> been updated to reflect 7/8.
>
> **Post-design update (2026-08-15):** forge v0.8 (IMPL-0009;
> registry issue #14) removes the legacy `choice`/`choices`/
> `validate` variable forms. The blueprint.hcl above now uses the
> v0.8 syntax; go/k8s targets v0.8 and the rest of the registry
> migrates separately. Implementation plan: IMPL-0002.

### 1. Blueprint-time flags vs chart-values toggles for monitoring?

**Decision: a** — both layers.

The design proposes both layers: `enable_monitoring` (blueprint)
controls whether the ServiceMonitor/PrometheusRule files exist at
all; `serviceMonitor.enabled` / `prometheusRule.enabled` (chart
values) control install-time rendering, defaulting off.

- **a.** Keep both layers. Blueprint flag for teams that never run
  Prometheus (no dead files in their repo); values toggle for
  everyone else (standard chart UX, matches repo-guardian).
  Recommended.
- **b.** Values toggle only — always ship the templates. Simpler
  blueprint, slightly noisier scaffold for non-Prometheus shops.
- **c.** Blueprint flag only — shipped files always render. Breaks
  the chart convention of install-time opt-in.

### 2. Drop repo-guardian's backend templates (valkey/postgres/cnpg/tailscale) entirely?

**Decision: a** — drop entirely.

The seeded chart carries them but the scrubbed values.yaml doesn't —
currently broken (defect 1).

- **a.** Drop them entirely. They're repo-guardian domain logic; a
  generic Go service blueprint shouldn't presuppose a queue or
  store. If a "service with baked postgres" shape recurs, add it
  later as a flag or sibling blueprint. Recommended.
- **b.** Keep behind blueprint flags (`enable_queue`,
  `enable_store`, `enable_tailscale`) — restores the values
  sections + schema defs, ships conditionally. Powerful but
  triples the chart surface to maintain and test.
- **c.** Keep as commented examples in the chart with a README
  pointer (dead code risk).

### 3. Keep the PrometheusRule starter alert pack?

**Decision: a** — generic two-alert starter pack.

repo-guardian's `prometheusrule.yaml` embeds a curated alert pack
referencing repo-guardian metric names.

- **a.** Keep the file but reduce to two generic starter alerts
  that only use kube-state/container metrics
  (replicas-unavailable, container-restarting) — demonstrates the
  pattern without app metric names. Recommended.
- **b.** Empty rule group with a how-to comment — pure skeleton.
- **c.** Drop `prometheusrule.yaml`; ship only ServiceMonitor.

### 4. Makefile in go/k8s?

**Decision: a** — drop; defer to DESIGN-0002 via inheritance.

Seeded Makefile is repo-guardian's verbatim (monitoring machinery,
chart-alerts). The blueprint inherits `justfile.tmpl` +
`Makefile.tmpl` from `go/_defaults` regardless.

- **a.** Drop the seeded Makefile; rely on go/_defaults inheritance
  (DESIGN-0002's Makefile decision applies here automatically).
  Recommended.
- **b.** Rewrite as a k8s-flavored `Makefile.tmpl` with helm
  targets overriding the inherited one — only if make parity for
  helm recipes matters to you.

### 5. Where does the ECR operator-prep doc live?

**Decision: a** — repo root docs/, shipped only for ecr.

Seeded at `charts/${project_name}/docs/publishing-to-ecr.md` (IAM
role trust policy, ECR repo creation, secrets setup).

- **a.** Move to repo root `docs/publishing-to-ecr.md`, shipped only
  when `container_registry == "ecr"`. It's operator documentation
  for the repo, not chart content — in the chart dir it gets
  packaged into the .tgz where it's useless. Recommended.
- **b.** Fold into README.md as a conditional section — one less
  file, branchier README template.
- **c.** Keep in the chart docs/ dir as seeded.

### 6. Keep gh-pages.yml (mkdocs docs site)?

**Decision: a** — drop.

repo-guardian publishes an mkdocs site; the registry's Go blueprints
don't currently ship docs-site workflows.

- **a.** Drop `gh-pages.yml` from go/k8s; docs-site publishing is a
  per-project decision and the docz/mkdocs stack is already
  available via defaults when wanted. Recommended.
- **b.** Keep behind an `enable_docs_site` blueprint flag.
- **c.** Keep unconditionally as seeded.

### 7. Local kind-based chart install testing (`ct install`)?

**Decision: a**, plus k3d recipes for the local loop (k3d-up/install/uninstall/down) replacing repo-guardian's docker-compose local testing. CI keeps kind + ct install deliberately — repo-guardian already evaluated k3d for CI helm testing and kept kind because k3d lacked a needed capability; kind is also the chart-testing ecosystem's first-class path.

Seeded `helm.just` has `helm-ct-install` (kind install test);
repo-guardian's CI `helm-test` job runs it with a kind cluster.

- **a.** Keep `ct install` in CI (the seeded `helm-test` job) but
  drop the local recipe — local kind lifecycle is fiddly and the CI
  job is the real gate. Recommended.
- **b.** Keep both the CI job and the local recipe.
- **c.** Drop both; helm-unittest + lint + template is enough
  (faster CI, no kind dependency).

### 8. Keep ghcr.yml/ecr.yml as reusable (`workflow_call`) workflows or inline into release.yml?

**Decision: b** — self-contained per-registry release workflows (release-ghcr.yml.tmpl / release-ecr.yml.tmpl → rendered as release.yml). Blueprint choice drives the whole release train; future registries are one file + one condition + one choice value. workflow_dispatch retained on each variant for ad-hoc republish.

Seeded pattern: release.yml → `uses:` → registry workflow, which
also exposes `workflow_dispatch` for ad-hoc republish + dry-run.
Since only one registry workflow ships per scaffold, the indirection
could be collapsed.

- **a.** Keep the reusable split as seeded. The `workflow_dispatch`
  path (ad-hoc republish of a tag, dry-run mode) is operationally
  useful and repo-guardian battle-tested it. Recommended.
- **b.** Inline the publish jobs into release.yml at template time —
  one less file, loses ad-hoc dispatch.

### 9. Chart-scoped changelog (chart cliff.toml + CHANGELOG.md)?

**Decision: a** — keep both cliff configs.

repo-guardian keeps a separate chart changelog
(`--include-path 'charts/**'`) beside the root one; the chart
versions independently.

- **a.** Keep both cliff configs as seeded (root + chart). The chart
  is a separately-versioned OCI artifact; its own changelog matches
  how consumers see it. Recommended.
- **b.** Root changelog only; chart version notes live in release
  notes.

## References

- [donaldgifford/repo-guardian](https://github.com/donaldgifford/repo-guardian) —
  reference implementation this blueprint generalizes
- `go/docker/` — docker-bake + docker.just pattern reused here
- [DESIGN-0002](./0002-align-gostd-blueprint-with-hclkit-conventions.md) —
  go/_defaults decisions this blueprint inherits
- [IMPL-0002](../impl/0002-gok8s-blueprint-templating-helm-chart-and-registry-flagged-ci.md) —
  phased implementation plan for this design
- [forge-registry#14](https://github.com/donaldgifford/forge-registry/issues/14) —
  registry-wide migration to forge v0.8 variable syntax (go/k8s
  lands on v0.8 first; the sweep follows)
- [forge MIGRATION.md — variable type system upgrade](https://github.com/donaldgifford/forge/blob/main/docs/MIGRATION.md#variable-type-system-upgrade-v07) —
  choice/validate removal and the `validation` block forms
- PR #11 — `${project_name}/` wrapper flatten (why the seeded rename
  block is dead config)
- PR #10 — HCL2 template syntax migration (why Helm's `{{ }}` needs
  no escaping in `.tmpl` files)
- [helm-unittest](https://github.com/helm-unittest/helm-unittest),
  [chart-testing](https://github.com/helm/chart-testing),
  [helm-docs](https://github.com/norwoodj/helm-docs) — chart CI
  toolchain baked into this blueprint
