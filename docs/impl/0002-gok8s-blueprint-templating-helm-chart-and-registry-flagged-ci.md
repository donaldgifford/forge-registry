---
id: IMPL-0002
title: "go/k8s Blueprint: Templating, Helm Chart, and Registry-Flagged CI"
status: Draft
author: Donald Gifford
created: 2026-08-15
---

<!-- markdownlint-disable-file MD025 MD041 -->

# IMPL 0002: go/k8s Blueprint: Templating, Helm Chart, and Registry-Flagged CI

**Status:** Draft **Author:** Donald Gifford **Date:** 2026-08-15

<!--toc:start-->

- [Objective](#objective)
- [Scope](#scope)
  - [In Scope](#in-scope)
  - [Out of Scope](#out-of-scope)
- [Verified Forge Behavior](#verified-forge-behavior)
- [Implementation Phases](#implementation-phases)
  - [Phase 1: Prune the Seed](#phase-1-prune-the-seed)
  - [Phase 2: blueprint.hcl Rewrite](#phase-2-blueprinthcl-rewrite)
  - [Phase 3: Chart Templating](#phase-3-chart-templating)
  - [Phase 4: Task Runner and Local Tooling](#phase-4-task-runner-and-local-tooling)
  - [Phase 5: CI and Release Workflows](#phase-5-ci-and-release-workflows)
  - [Phase 6: Verification and Landing](#phase-6-verification-and-landing)
- [File Changes](#file-changes)
- [Testing Plan](#testing-plan)
- [Open Questions](#open-questions)
- [Dependencies](#dependencies)
- [References](#references)
<!--toc:end-->

## Objective

Turn the repo-guardian-seeded `go/k8s/` tree into a working blueprint per
DESIGN-0004: a Go service that ships a distroless container image (the
`go/docker` pipeline) plus a templated Helm chart, with chart CI baked in
(helm-unittest, chart-testing, helm-docs) and a self-contained release train
that publishes image + chart to GHCR or ECR based on the `container_registry`
variable chosen at `forge create` time.

**Implements:** DESIGN-0004 — go/k8s Blueprint: Go Service with Helm Chart and
Registry-Flagged CI (all 9 design questions resolved 2026-08-15).

**Targets forge v0.8** (the IMPL-0009 variable-type release;
[forge-registry#14](https://github.com/donaldgifford/forge-registry/issues/14)):
go/k8s is written in v0.8 blueprint syntax from the start. The installed v0.7
binary cannot load it; the rest of the registry migrates to v0.8 separately
(issue #14's scope, not this PR's).

Tasks tagged `(OQ-n)` implement the decided option for that question — all five
were resolved 2026-08-15 with option **a** (OQ-1 as "target forge v0.8").

## Scope

### In Scope

- Everything under `go/k8s/` on branch `feat/go-k8s`: blueprint.hcl, chart,
  workflows, helm.just, ct.yaml, mise/README templates.
- One shared-file edit in `go/_defaults/justfile.tmpl` per the OQ-3 decision
  (optional `import?` lines for `docker.just` / `helm.just`).
- `registry.hcl` entry for `go/k8s` via `forge registry update`.

### Out of Scope

- DESIGN-0002 (hclkit / go/std alignment) — whatever lands in `go/_defaults` is
  inherited here automatically.
- The registry-wide migration to forge v0.8 variable syntax (issue #14) — go/k8s
  just lands on v0.8 first; the other ~13 blueprint.hcl files keep their legacy
  forms until that sweep.
- Changes to the `forge` CLI itself.
- repo-guardian backends (valkey/postgres/CNPG/tailscale/policy) — dropped per
  design Q2a, not re-implemented behind flags.

## Verified Forge Behavior

The design flagged four mechanisms for implementation-time verification. All
four are now verified against the forge source at `~/code/forge` (installed
binary: `forge 0.7.0`, commit `585dddd`; forge HEAD carries the IMPL-0009
variable-type overhaul, shipping as **v0.8**). Findings:

1. **forge v0.8 removes the legacy variable forms.** `vartype.go` hard-errors on
   `type = "choice"`, and MIGRATION.md confirms `choices` and the single-regex
   `validate` attribute are rejected at load time too — enums become
   `validation { condition = contains(...) }` blocks, regexes become
   `can(regex(...))` (issue #14 tracks the registry-wide migration).
   `type = bool` works on both versions. The installed v0.7 binary does **not**
   understand `validation` blocks, so a v0.8-syntax blueprint cannot load on it
   — go/k8s therefore requires a forge v0.8 install from Phase 2 on (OQ-1,
   resolved).
2. **`condition.exclude` entries are evaluated at blueprint-load time with a nil
   EvalContext** (`loader_hcl_helpers.go:124`) — a bare `${project_name}` inside
   an exclude string is a load error. Write `$${project_name}` so HCL emits the
   literal `${project_name}`, which exactly matches the literal source directory
   name `charts/${project_name}/`. Patterns are matched with `filepath.Match` +
   a directory-prefix fallback against **source** relative paths — i.e.
   including the `.tmpl` extension (`create/conditions.go:49`). Globs like
   `charts/*/templates/servicemonitor.yaml*` also work; `$`, `{`, `}` are not
   glob metacharacters.
3. **`rename.entry.from` supports variable interpolation** — the pattern is
   rendered with the resolved variables (`RenderPath`) and prefix-matched
   against each file's rendered path _before_ the `.tmpl` strip
   (`create/create.go:350`). A pattern that matches no file is a no-op, so the
   condition-excluded release variant is safe. The design's single rename entry
   (`from = ".github/workflows/release-${container_registry}.yml"`) works as
   written: the prefix match carries a trailing `.tmpl` into the replacement,
   which is then stripped.
4. **Defaults-inheritance overrides are exact-relpath, `.tmpl`-blind**
   (`defaults/resolver.go`, FileSet keyed by source relpath). A blueprint
   `ci.yml.tmpl` does _not_ replace an inherited `ci.yml` in the file set — both
   render to the same output path and the blueprint copy merely wins by write
   order. The clean mechanism is the `defaults { exclude = [...] }` block (exact
   relpaths, no globs), which go/k8s needs anyway: `go/_defaults` ships
   `.github/workflows/release.yml` (goreleaser train) that would collide with
   the renamed per-registry release workflow.

Two additional facts discovered during research that the design did not cover:

- **Inherited variable surface**: `go/_defaults` templates reference
  `project_org`, `git_host`, `renovate_config_prefix`, and the four Backstage
  `project_component_*` variables (catalog-info.yaml.tmpl). The design's
  8-variable prompt list would fail rendering inherited templates; go/k8s must
  declare the full surface or exclude the files (OQ-2).
- **No blueprint currently imports `docker.just`** — go/docker ships it unwired
  (standalone `just -f docker.just` only), and `go/_defaults/justfile.tmpl` has
  no `import` lines. How `helm.just` joins the main justfile is a real decision,
  not an inherited pattern (OQ-3).

## Implementation Phases

Each phase builds on the previous one. A phase is complete when all its tasks
are checked off and its success criteria are met. All open questions are
resolved (option **a** throughout), so nothing gates on decisions — Phase 1 can
start immediately, and Phase 2 onward needs a forge v0.8 install.

---

### Phase 1: Prune the Seed

Delete everything repo-guardian-specific that has no generic successor, and
collapse the raw-copy/template duplicates. Pure removals and moves — no content
edits yet.

#### Tasks

- [x] Delete the 10 backend chart templates under
      `charts/${project_name}/templates/`: `queue-valkey.yaml`,
      `queue-valkey-secret.yaml`, `store-postgres.yaml`,
      `store-postgres-secret.yaml`, `store-cnpg-cluster.yaml`,
      `store-cnpg-pooler.yaml`, `store-cnpg-pooler-service.yaml`,
      `tailscale-configmap.yaml`, `tailscale-rbac.yaml`, `policy-configmap.yaml`
- [x] Delete the 3 backend-coupled test files under
      `charts/${project_name}/tests/`: `backend_shapes_test.yaml`,
      `policy_test.yaml`, `deployment_env_test.yaml`
- [x] Delete the raw duplicates: `mise.toml` (keep `mise.toml.tmpl`),
      `charts/${project_name}/README.md.gotmpl` (keep `README.md.gotmpl.tmpl`),
      `charts/${project_name}/README.md` (generated artifact; the gotmpl is the
      source)
- [x] Delete `Makefile` (design Q4a — go/\_defaults inheritance supplies it)
- [x] Delete `.github/workflows/gh-pages.yml` (design Q6a)
- [x] (OQ-4) Delete `.github/workflows/changelog-update.yml` — root changelog
      regen is covered by the inherited `changelog.yml`/`changelog-regen.yml`
      pair; the chart changelog is regenerated inside the publish workflow
      (`git-cliff-action` step in the seeded ghcr/ecr chart job)
- [x] Move `charts/${project_name}/docs/publishing-to-ecr.md` to
      `docs/publishing-to-ecr.md` (repo root; design Q5a) and remove the
      now-empty chart `docs/` dir. Content scrub happens in Phase 5.
- [x] Diff the seeded `.github/workflows/{security,license-check,pr-labels}.yml`
      and `.github/labeler.yml` against the `go/_defaults` copies; delete any
      seeded copy that is identical or strictly worse (keep the seeded copy only
      where it carries k8s-specific value, e.g. chart path labels in
      `labeler.yml`). Outcome: all four deleted — `pr-labels.yml` was identical;
      `security.yml` predates the defaults' `govulncheck-action` consolidation;
      `license-check.yml` differed only in a checkout version (renovate's job);
      `labeler.yml` was a stale fork (old schema modeline, missing branch-prefix
      labels) with no chart rules to preserve
- [x] (Added during execution) Delete the seeded root `CHANGELOG.md` — it was an
      empty file shadowing the inherited `go/_defaults/CHANGELOG.md`
      Keep-a-Changelog seed

#### Success Criteria

- `find go/k8s -type f` contains no `queue-*`, `store-*`, `tailscale-*`, or
  `policy-*` files, no raw `mise.toml`, no `Makefile`, no `gh-pages.yml`, and
  exactly one of each remaining basename (no raw/`.tmpl` duplicate pairs)
- The only seeded workflow names that shadow `go/_defaults` names are deliberate
  overrides (at minimum `ci.yml`)
- `grep -rl repo-guardian go/k8s/` matches only files scheduled for templating
  in Phases 3–5 (chart files, helm.just, workflows, README)

---

### Phase 2: blueprint.hcl Rewrite

Replace the forge-init starter with the full variable surface, conditions,
rename, defaults-exclusions, and hooks — in forge v0.8 syntax (OQ-1 decision),
using only mechanisms verified against forge (see
[Verified Forge Behavior](#verified-forge-behavior)). Requires a forge v0.8
install to verify (`forge info` / `forge create`); the v0.7 binary rejects
`validation` blocks.

#### Tasks

- [x] Set header fields: `name = "go-k8s"`, description, `version = "0.1.0"`,
      `tags = ["go", "k8s", "helm", "docker"]`
- [x] Declare the design's blueprint variables in v0.8 syntax — the full block
      is spelled out in DESIGN-0004's updated blueprint.hcl sketch:
      `project_name` / `project_owner` (string, required,
      `validation { can(regex("^[a-z][a-z0-9-]*$", ...)) }`),
      `project_description` (string, required), `license` (string, default
      Apache-2.0, `validation { contains([...]) }`), `go_version` (string,
      default `1.26`), `container_registry` (string, default `ghcr`,
      `validation { contains(["ghcr", "ecr"]) }`), `enable_monitoring` /
      `enable_helm_docs` (`type = bool`, default `true`)
- [x] (OQ-2) Declare the inherited-template variables: `project_org` (default
      `"${project_owner}"`), `git_host` (default `"github.com"`),
      `renovate_config_prefix` (default `"github"`), and the four required
      Backstage vars `project_component_type`, `project_component_system`,
      `project_component_lifecycle`, `project_component_owner` — no
      `git_provider` prompt (the release stack is GitHub-only)
- [x] Remove the dead `${project_name}/ → .` rename block (defect 7) and add the
      verified release rename:

      ```hcl
      rename {
        entry {
          from = ".github/workflows/release-${container_registry}.yml"
          to   = ".github/workflows/release.yml"
        }
      }
      ```

- [x] Add the registry conditions (paths assume OQ-5a plain-`.yml` workflows;
      append `.tmpl` if OQ-5b is chosen):

      ```hcl
      condition {
        when    = container_registry != "ghcr"
        exclude = [".github/workflows/release-ghcr.yml"]
      }

      condition {
        when    = container_registry != "ecr"
        exclude = [
          ".github/workflows/release-ecr.yml",
          "docs/publishing-to-ecr.md*",
        ]
      }
      ```

- [x] Add the monitoring / helm-docs conditions (note the `$${...}` literal
      escape; the trailing `*` glob matches source paths both before and after
      Phase 3 adds the `.tmpl` extensions):

      ```hcl
      condition {
        when    = !enable_monitoring
        exclude = [
          "charts/$${project_name}/templates/servicemonitor.yaml*",
          "charts/$${project_name}/templates/prometheusrule.yaml*",
          "charts/$${project_name}/tests/servicemonitor_test.yaml*",
          "charts/$${project_name}/tests/prometheusrule_test.yaml*",
        ]
      }

      condition {
        when    = !enable_helm_docs
        exclude = ["charts/$${project_name}/README.md.gotmpl*"]
      }
      ```

- [x] (OQ-4) Add the inherited-file exclusions:

      ```hcl
      defaults {
        exclude = [
          ".github/workflows/release.yml",
          ".goreleaser.yml.tmpl",
        ]
      }
      ```

      Exact relpaths only — this block does not glob. Extend it in
      Phase 5 for any inherited workflow that go/k8s replaces with a
      differently-named source file (`.tmpl` variants included, since
      overrides are `.tmpl`-blind)

- [x] Set `hooks { post_create = ["git init", "go mod tidy"] }`
- [x] Fix `charts/.yamllint.yml.tmpl`: `${chart_name}` → `${project_name}`
      (defect 8 — do it here so the Phase 2 scaffold renders without
      unknown-variable errors)

#### Success Criteria

- `forge info go/k8s/blueprint.hcl` loads cleanly on forge v0.8 (the v0.7 binary
  rejecting the `validation` blocks is expected, not a failure)
- File-set matrix over `forge create go/k8s ... --defaults --set ...` scaffolds
  (ghcr/ecr × monitoring on/off, plus helm-docs off):
  - exactly one `.github/workflows/release.yml` in every scaffold, and no
    `release-ghcr.yml` / `release-ecr.yml` leftovers
  - `docs/publishing-to-ecr.md` present only when `container_registry=ecr`
  - servicemonitor/prometheusrule templates + tests absent when
    `enable_monitoring=false`; `README.md.gotmpl` absent when
    `enable_helm_docs=false`
- The scaffold renders with **zero** unknown-variable errors (proves the
  inherited variable surface is complete — chart files are still verbatim copies
  at this point, which is expected)

Execution notes (2026-08-15, verified on forge 0.8.0):

- `forge info` loads clean; the 4-case matrix (defaults / ecr / monitoring-off /
  helm-docs-off) scaffolds 80/81/76/79 files with every presence/absence
  assertion passing, zero render errors, and the registry choice driving the
  shipped `release.yml` content (GHCR vs ECR train).
- Pulled the `ghcr.yml → release-ghcr.yml` / `ecr.yml → release-ecr.yml` file
  renames forward from Phase 5 so the conditions + rename verify against real
  filenames; the content rework stays in Phase 5.
- The seeded dispatcher `release.yml` currently loses the same-output write race
  to the renamed train (the scaffold's `release.yml` is already the publish
  workflow). Phase 5 deletes the dispatcher after folding its bump-version job
  into the trains, which removes the ambiguity.
- Discovered and fixed two `go/_defaults` files that referenced forge variables
  without being templates, shipping literal `${...}` into every go scaffold:
  `.github/dependabot.yml` → `dependabot.yml.tmpl` (three `${project_owner}`
  reviewer entries) and `.gitignore` → `.gitignore.tmpl` (`/${project_name}`
  binary ignore). Registry-wide fix; rendering verified post-rename.

---

### Phase 3: Chart Templating

Generalize the chart: every `repo-guardian` reference becomes `${project_name}`
/ `${project_owner}`, every file gaining a forge variable gains the `.tmpl`
extension (forge strips it on output), and the values/schema/tests are
reconciled with the scrubbed values shape (defect 1). Helm's `{{ }}` syntax
passes through HCL2 untouched; only shell-style `${...}` needs the `$${...}`
escape.

#### Tasks

- [x] `templates/_helpers.tpl` → `_helpers.tpl.tmpl`: rename all
      `repo-guardian.*` helper definitions to `${project_name}.*` (29
      occurrences); keep `validateTemplatingVars` / `validateRemovedValues` but
      prune their rule lists to the values that survive the scrub (removed
      backend keys become `validateRemovedValues` entries so operators upgrading
      get a fail-fast message)
- [x] Template the 8 kept `templates/` files (each → `.tmpl`, includes renamed
      to `${project_name}.*`):
  - `deployment.yaml` — also strip the backend env wiring
    (`validateBackendSecrets` include, queue/store env blocks)
  - `service.yaml`, `serviceaccount.yaml`
  - `configmap.yaml`, `secret.yaml` — generalize to app config (drop
    repo-guardian appId/webhookSecret/privateKey shapes)
  - `NOTES.txt` — mind `$${...}` for any shell examples
  - `servicemonitor.yaml`
  - `prometheusrule.yaml` — replace the repo-guardian alert pack with the
    generic two-alert starter (design Q3a): replicas-unavailable
    (`kube_deployment_status_replicas_unavailable`) and container-restarting
    (`increase(kube_pod_container_status_restarts_total[15m])`), alert names
    prefixed from the chart fullname
- [x] Template the 8 kept `tests/` files (each → `.tmpl`): deployment, service,
      serviceaccount, configmap, secret, servicemonitor, prometheusrule,
      values_guard — assertions updated for the scrubbed values and renamed
      helpers
- [x] `values.schema.json` → `.tmpl`: drop the
      `queue`/`store`/`tailscale`/`policy` property definitions (schema half of
      defect 1); template the `image.repository` default
      (`ghcr.io/${project_owner}/${project_name}` for ghcr; for ecr leave a
      commented placeholder — the account ID isn't known at scaffold time)
- [x] `values.yaml.tmpl`: verify the post-scrub shape matches the kept templates
      (image, ports, probes, serviceAccount, resources,
      `serviceMonitor.enabled: false`, `prometheusRule.enabled: false`);
      template `image.repository` to match the schema default
- [x] `Chart.yaml.tmpl`: verify `name: ${project_name}`, description from
      `${project_description}`, `version: 0.1.0`, sane `appVersion`
- [x] `ci/ci-values.yaml`: replace the repo-guardian secret overrides
      (appId/webhookSecret/privateKey) with the minimal generic values a
      `ct install` / `helm template -f` run needs
- [x] `cliff.toml.tmpl` (chart): verify chart-scoped config
      (`--include-path 'charts/**'` model, design Q9a); `CHANGELOG.md.tmpl`:
      seed empty/minimal
- [x] `README.md.gotmpl.tmpl`: scrub repo-guardian prose; keep the helm-docs
      value/section structure
- [x] Verify `.helmignore` needs no templating (stays verbatim)

#### Success Criteria

- On a `--defaults` scaffold: `helm lint charts/<name>` passes,
  `helm template <name> charts/<name>` renders with **zero overrides** (defect 1
  closed), and `helm unittest charts/<name>` passes
- An `enable_monitoring=false` scaffold still lints, templates, and unit-tests
  clean (no dangling refs to the excluded files)
- `grep -ri repo-guardian <scaffold>/charts/` returns nothing

Execution notes (2026-08-15, verified on helm v3.19 + helm-unittest 1.0.3):

- All criteria pass: `helm lint` clean, `helm template` renders 3 resources with
  zero overrides (Deployment/Service/ServiceAccount — ConfigMap, Secret, and
  monitoring correctly absent by default), 45/45 unit tests across 8 suites; the
  monitoring-off scaffold passes 33/33 across 6 suites; zero repo-guardian
  references in `charts/`.
- Generic env contract introduced to replace the repo-guardian config shape:
  `config.port`/`config.metricsPort`/`config.logLevel` render as
  `LISTEN_ADDR`/`METRICS_ADDR`/`LOG_LEVEL` (+ `POD_NAME` fieldRef);
  `configMap.data` and `secrets.stringData` project into chart-managed
  ConfigMap/Secret injected via `envFrom`; `command` override kept for the
  ci-values busybox stand-in pattern.
- Guard helpers: `validateTemplatingVars`/`validateBackendSecrets` were
  repo-guardian-specific and their subjects are gone — generalized into one
  `validateEnvCollisions` guard (extraEnv/configMap.data/secrets.stringData vs
  the chart-managed env names, same fail-fast pattern, unit-tested in
  `values_guard_test`); `validateRemovedValues` kept as a documented empty shell
  (nothing removed at chart 0.1.0).
- Deviation from the design text: Prometheus alert names cannot contain hyphens,
  so "names prefixed from the chart fullname" is invalid — the starter alerts
  are `DeploymentReplicasUnavailable` / `ContainerRestarting`, scoped to the
  release via namespace + deployment/container labels in the expression.
  Per-alert overrides use `hasKey` guards so explicit `enabled: false` /
  `threshold: 0` are honored (sprig `default` treats falsy values as unset).
- Chart version and appVersion bumped `0.0.1` → `0.1.0`.
- Discovered and fixed another shared-defaults leak:
  `go/_defaults/Makefile.tmpl`'s `run` target hardcoded
  `./build/bin/repo-guardian` — now `$(BIN_DIR)/$(PROJECT_NAME)`, matching
  `run-local` (affects every go blueprint).

---

### Phase 4: Task Runner and Local Tooling

Rewrite `helm.just` as a clean just module (defect 3), add the k3d local loop
(design Q7 rider), fix the small config defects, and wire the module into the
main justfile.

#### Tasks

- [x] Rewrite `helm.just` → `helm.just.tmpl` per the design sketch:
      `chart_root`/`chart_dir` just-variables; recipes `helm-lint` (helm lint +
      ct lint), `helm-template`, `helm-template-ci`, `helm-unittest`,
      `helm-test` (lint + unittest), `helm-docs`, `helm-push` (registry ref
      templated per `container_registry`); remove all Makefile idioms
      (`$(MAKE) log-$@`, `## suffix` comments), the undefined
      `{{ project_name }}` just-variable, and the repo-guardian `--set` flags
- [x] Add the k3d recipe group to `helm.just.tmpl`: `k3d-up`, `k3d-down`,
      `k3d-install` (bake →
      `k3d image import     ghcr.io/${project_owner}/${project_name}:dev` →
      `helm upgrade     --install` with ci-values + `image.tag=dev`
      `image.pullPolicy=Never`), `k3d-uninstall`
- [x] Add a `helm-plugins` bootstrap recipe
      (`helm plugin install     helm-unittest`, idempotent) — helm-unittest is a
      helm plugin, not a mise-installable tool
- [x] `mise.toml.tmpl`: add renovate-annotated pins for `helm`, chart-testing
      (`ct`), `helm-docs`, and `k3d` (exact mise tool names verified at
      implementation time); `kubectl` optional for the k3d loop
- [x] `ct.yaml`: replace the wrong `helm-testsuite.json` schema line (defect 6)
      with the same "chart-testing publishes no JSON schema" comment used in
      `bun/std/ct.yaml`
- [x] (OQ-3) Add `import? 'docker.just'` and `import? 'helm.just'` (optional
      imports, just ≥ 1.33) to `go/_defaults/justfile.tmpl` — no-ops for
      blueprints without the modules, wires go/docker's module as a side effect
- [x] Root `README.md.tmpl`: scrub repo-guardian content; document the chart
      layout, `just helm-*` recipes, and the k3d loop
      (`k3d-up → k3d-install → iterate → k3d-down`)

#### Success Criteria

- In a `--defaults` scaffold: `just --list` shows the `helm` and `k3d` recipe
  groups alongside the inherited + docker recipes
- `just helm-lint`, `just helm-template`, `just helm-unittest`, and
  `just helm-docs` all run green in the scaffold
- The k3d loop verified once end-to-end on a scaffold: `just k3d-up`,
  `just k3d-install`, deployment reaches Ready, `just k3d-down`
- `yamllint` accepts the rendered `charts/.yamllint.yml`; no `just` parse errors
  anywhere (`just --list` exits 0)

> **Phase 4 execution notes (2026-08-15):**
>
> - **Makefile removed from the go tree (user-directed scope addition).**
>   Deleted `go/_defaults/Makefile.tmpl`; the justfile is now the single task
>   runner for go blueprints. Dropped the `makefmt`/`checkmake` pins from
>   `go/_defaults/mise.toml.tmpl`, `go/ext/mise.toml.tmpl`, and
>   `go/k8s/mise.toml.tmpl`; updated the header comment in
>   `go/_defaults/justfile.tmpl`. Exceptions kept as-is: `go/kubebuilder`
>   retains its pins and make-wrapping justfile (kubebuilder generates a real
>   Makefile users extend); the `Makefile` glob in
>   `go/_defaults/.github/labeler.yml` stays (harmless elsewhere, still correct
>   for kubebuilder); root `_defaults/justfile.tmpl` and the rust tree are
>   untouched (rust still ships a Makefile — issue #14 migration scope). This
>   also settles DESIGN-0002's dormant dual-task-runner question for go.
> - `docker.just.tmpl` dropped its own `set shell` line — just 1.51 errors on
>   duplicate settings across imports (verified: "setting `shell` first set on
>   line 1 is redefined"). Settings live only in the root justfile.
> - `k3d-install` deviates from the sketch: it does **not** use ci-values (those
>   swap the image for busybox — wrong for a dev-image loop); it installs the
>   real chart with `image.tag=dev image.pullPolicy=Never`.
>   `helm-package`/`helm-push` package into `build/charts/`; the ECR variant
>   guards on an `ECR_REGISTRY` env var instead of a templated registry ref
>   (account id/region are deploy-time facts, not scaffold-time).
> - `docker-bake.hcl.tmpl`: removed the `linux/amd64` platforms pin from the
>   default (local) target so `just docker-build` produces a host-native image
>   that actually runs in k3d on arm64 hosts.
> - Hooks cannot interpolate variables (`forge create` fails "Variables not
>   allowed" at decode) — so instead of a `go mod init` hook the blueprint now
>   ships `go.mod.tmpl` (`module ${git_host}/${project_owner}/${project_name}`,
>   `go ${go_version}`), which also satisfies the Dockerfile's `COPY go.*` and
>   makes the `go mod tidy` hook valid on a fresh scaffold.
> - mise pins added to `go/k8s/mise.toml.tmpl`: `helm = "3.19.0"`,
>   `helm-ct = "3.14.0"`, `helm-docs = "1.14.2"`, `k3d = "5.8.3"` (kubectl
>   omitted — not needed by any recipe). Root `README.md.tmpl` was empty, not
>   repo-guardian content — authored fresh (env contract, recipes, layout,
>   release flow, conditional GHCR/ECR install section).
> - Verified in `--defaults` and `container_registry=ecr` scaffolds (80/81
>   files): `just --list` exits 0 with `[docker]`/`[helm]`/`[k3d]` groups;
>   `helm-lint` (helm + ct), `helm-template`, `helm-unittest` (45/45),
>   `helm-docs`, `helm-package` all green; `yamllint -c charts/.yamllint.yml`
>   clean; ECR variant renders the `ECR_REGISTRY` guard and no `helm_oci` ref.
>   k3d loop: dev image built host-native via `just docker-build` against a
>   throwaway `cmd/` service honoring the env contract; the live cluster-install
>   step was skipped per user — recipes are standard k3d/helm invocations,
>   verified by inspection.

---

### Phase 5: CI and Release Workflows

Generalize `ci.yml`, and collapse the seeded `release.yml → ghcr.yml/ecr.yml`
reusable-workflow indirection into two self-contained per-registry release
trains (design Q8b). Approach for de-repo-guardian-ing the workflows is OQ-5;
tasks below assume OQ-5a (repo-agnostic via GitHub context, files stay plain
`.yml`).

#### Tasks

- [x] `ci.yml`: drop the `lint-alerts` and `monitoring-drift` jobs (defect 9);
      keep changes-detection, labeler, lint, test-go, security, build,
      docker-build, helm-unittest, helm-test
- [x] `ci.yml`: replace hardcoded `charts/repo-guardian/...` paths with
      chart-agnostic forms (`charts/**` in the changes filter, `charts/*/` globs
      in helm commands) and the codecov slug with `$GITHUB_REPOSITORY` context
- [x] `ci.yml`: make the helm-docs step degrade gracefully when
      `enable_helm_docs=false` (guard on `README.md.gotmpl` existence, or drop
      the step if the seeded CI has none)
- [x] Build `release-ghcr.yml` from the seeded `ghcr.yml`: prepend the
      `bump-version` job from the seeded `release.yml`
      (jefflinse/pr-semver-bump; major/minor/patch/dont-release labels — already
      created by `scripts/labels.sh`); replace the `workflow_call` trigger with
      `push: branches: [main]` + `workflow_dispatch` (keep `tag` and `dry_run`
      inputs); rewire `inputs.tag` references to coalesce dispatch input vs.
      bump-version output; keep the image/chart publish + cosign + SLSA jobs as
      seeded
- [x] `release-ghcr.yml` env block: derive `IMAGE_REPO` from
      `github.repository`, `CHART_NAMESPACE` from `github.repository_owner` +
      `/charts`, `CHART_NAME` from the repo name (OQ-5a; with OQ-5b these become
      `${project_owner}/${project_name}` etc. in a `.tmpl`)
- [x] `release-ghcr.yml` chart job: resolve the chart directory dynamically (one
      step writing `CHART_DIR=$(echo charts/*/)` to `GITHUB_ENV`) so the
      git-cliff config, `Chart.yaml` read, package, and push steps stop
      hardcoding `charts/repo-guardian`
- [x] Build `release-ecr.yml` from the seeded `ecr.yml` the same way:
      bump-version job, push+dispatch triggers, dynamic chart dir; keep the
      aws-auth OIDC job and the `ECR_AWS_ACCOUNT_ID`/`ECR_REGION`/`ECR_ROLE_ARN`
      secret plumbing; point the operator-prep comments at the relocated
      `docs/publishing-to-ecr.md`
- [x] Delete the seeded `release.yml` (dispatcher) and the now-consumed
      `ghcr.yml` / `ecr.yml` source names once the trains exist
- [x] `docs/publishing-to-ecr.md`: scrub repo-guardian refs (repo names, chart
      OCI paths); align the secrets table with the release-ecr env block
- [x] `.github/labeler.yml`: Phase 1 deleted the stale seeded copy, so the
      inherited defaults labeler applies. Decide whether a `helm` (`charts/**`)
      / `docker` (`Dockerfile`) label rule is worth a blueprint override — note
      an override fully replaces the inherited file, so it must be a superset
      copy of `go/_defaults/.github/labeler.yml`
- [x] Update the Phase 2 `defaults { exclude }` list for any inherited workflow
      now replaced under a different source name (none needed under OQ-5a:
      `ci.yml` overrides by identical relpath)
- [x] Run `actionlint` on all workflow files in the registry source (OQ-5a keeps
      them plain YAML, so they lint at rest)

#### Success Criteria

- A ghcr `--defaults` scaffold: `.github/workflows/release.yml` is the complete
  GHCR train (bump-version → image + chart publish → SLSA); `actionlint` passes
  on every workflow in the scaffold
- An ecr scaffold: `release.yml` is the ECR train including aws-auth;
  `docs/publishing-to-ecr.md` present and consistent with the workflow's secret
  names
- `grep -ri "repo-guardian\|donaldgifford/repo" <scaffold>/.github/` returns
  nothing in any flag combination
- `ci.yml` in the scaffold contains no `lint-alerts` or `monitoring-drift` jobs

> **Phase 5 execution notes (2026-08-15):**
>
> - Both trains are fully self-contained (no reusable-workflow indirection):
>   `bump-version` (gated to `push`) → `image` / `chart` → `*-slsa`. The tag
>   coalesce is `${{ inputs.tag || needs.bump-version.outputs.tag }}` as a
>   job-level `TAG` env; job `if:` gates spell out the two paths explicitly with
>   `!cancelled()` to lift the implicit `success()` (env context is not
>   available in job-level `if:`, and reusable-workflow `with:` inputs can't
>   read `env` either — the SLSA jobs derive image refs from the `github`
>   context directly).
> - No goreleaser anywhere: the dispatcher's binary-release job (goreleaser +
>   GPG) was dropped, consistent with OQ-4's exclusion of `.goreleaser.yml` —
>   the shippable artifacts are the image and chart. `ci.yml`'s `build` job
>   became a plain `go build ./...` compile check for the same reason.
> - `ci.yml` extras beyond the task list: `labeler` gated to `pull_request`
>   (labeler@v6 errors on push events; the seeded job ran on both), `ct.yaml`
>   added to the `helm` changes filter, `Makefile` filter entries gone (Phase 4
>   removal). There was no helm-docs CI step in the seeded file, so none was
>   added.
> - The ECR train keeps the `ECR_PUBLISH_ENABLED` repo-variable gate from the
>   old dispatcher, moved onto the `aws-auth` job (dispatch runs bypass it), so
>   merges don't go red before the AWS prep is done — `bump-version` stays
>   ungated (tagging is registry-independent).
> - `docs/publishing-to-ecr.md` → `.md.tmpl` full rewrite (the Phase 2 exclude
>   glob `docs/publishing-to-ecr.md*` already covers the `.tmpl` name): reframed
>   from "unwired add-on recipe" to the armed-workflow walkthrough; secrets
>   table matches the train (`ECR_AWS_ACCOUNT_ID`/`ECR_REGION`/`ECR_ROLE_ARN`);
>   local push section uses `just helm-push` + `ECR_REGISTRY`.
> - Labeler override decision: **yes** — `go/k8s/.github/labeler.yml` is a
>   superset copy of the defaults adding `helm` (charts/\*\*, ct.yaml,
>   helm.just) and `docker` (Dockerfile, docker-bake.hcl, .dockerignore,
>   docker.just) rules; `labels.sh` creates labels from labeler.yml so the new
>   labels self-provision. The copy drops the `Makefile` glob and
>   `.goreleaser.yaml` entry (neither exists in a k8s scaffold).
> - Root `README.md.tmpl` release section corrected to the actual flow
>   (merge-to-main + PR semver labels, no goreleaser/tag-push).
> - Verified: `actionlint` + `yamllint` clean on the three source files; both
>   scaffold variants render exactly one `release.yml` (ghcr: 3 `ghcr.io` refs,
>   no aws-auth; ecr: aws-auth train + rendered ECR doc);
>   `grep -ri "repo-guardian\|donaldgifford/repo"` over both entire scaffold
>   trees returns nothing; `actionlint` passes on every workflow (inherited
>   defaults included) in both scaffolds.

---

### Phase 6: Verification and Landing

Run the design's full testing matrix against fresh scaffolds, sync the registry
index, and land the PR.

#### Tasks

- [x] `forge create go/k8s test-svc --defaults` scaffolds cleanly; both
      post-create hooks pass
- [x] `helm lint` + `helm template` (zero overrides) + `helm unittest` +
      `ct lint --config ct.yaml --all` all pass in the scaffold
- [x] `helm-docs` generates the chart README without error (helm-docs enabled
      scaffold)
- [x] `docker buildx bake --print` resolves
- [x] `actionlint` passes on all rendered workflows
- [x] Flag matrix re-run (final form): ecr-only release train; monitoring-off
      chart lints + unit-tests clean; helm-docs-off has no gotmpl and no CI docs
      step failure
- [x] `grep -ri "repo-guardian\|donaldgifford/repo" <scaffold>` → zero hits
      across the matrix
- [x] `forge registry update --registry-dir .` (run with v0.8) and verify the
      `go/k8s` entry in `registry.hcl` (name `go-k8s`, version `0.1.0`,
      description). Verified safe against unmigrated blueprints: entries whose
      blueprint.hcl fails to load are reported `missing` but left untouched in
      `registry.hcl` (`registrycmd/update.go` skips `StatusMissing`), so the
      legacy blueprints keep their index entries until the issue #14 sweep
- [x] `/registry-validate` clean; `/registry-review` pass over the final diff
- [x] Repo linters green: `yamllint`, `yamlfmt`, `markdownlint-cli2`, `prettier`
      (this doc included)
- [ ] Commit on `feat/go-k8s` and open the PR to `main` with the test matrix
      evidence in the description

> **Phase 6 execution notes (2026-08-15):**
>
> - **Upstream forge bug found:** post-create hooks never execute in forge v0.8
>   @ `806263d` — `hooks.RunPostCreate` exists and the `NoHooks` option is
>   plumbed into `internal/create/create.go`, but nothing in the create path
>   calls the runner (verified by source grep: zero non-test call sites). The
>   blueprint's hook declaration is correct and decodes (bad hook config fails
>   the load — observed when a `${var}` was tried in a hook string: "Variables
>   not allowed"). `git init` + `go mod tidy` were run manually in the matrix as
>   the stand-in; both are trivial and `go.mod` ships as a rendered file
>   regardless. Worth a forge issue.
> - Defaults scaffold (with hooks requested, 80 files): `helm lint`,
>   `helm template`, `helm unittest` 45/45, `ct lint --all`, `helm-docs`,
>   `docker buildx bake --print`, and `actionlint` all green.
> - Flag matrix: ecr (81 files — ECR train + rendered ECR doc, verified in Phase
>   5), monitoring-off (76 files, zero servicemonitor/prometheusrule, 33/33
>   unittests), helm-docs-off (79 files, zero gotmpl, no CI docs step exists to
>   fail). repo-guardian grep across all four full trees: zero hits.
> - `forge registry update`: `go/k8s` up-to-date; legacy blueprints warn
>   `missing` with entries preserved, as predicted. Caveat discovered: the
>   command only tracks version/git-commit drift — `description`/`tags` in
>   `registry.hcl` are not synced from blueprint.hcl, so the stale seeded entry
>   ("golang k8s service", 2 tags) was updated by hand to match
>   (`Go service with container image + Helm chart, ...`, 4 tags).
> - `/registry-validate` + `/registry-review` (both skills predate the HCL
>   migration; intent applied to the current schema): required fields, name
>   convention `go-k8s`, semver, enum lists, regex validity, zero undeclared
>   `${var}` refs across go/k8s + go/\_defaults `.tmpl` files, rename mapping
>   verified in both variants. The go/k8s `renovate.json5.tmpl` override is an
>   intentional superset of the registry default (adds
>   go/docker/helm/kubernetes/kustomize presets).
> - Repo linters on the changed surface: yamllint clean (go/k8s tree),
>   markdownlint clean, prettier applied to this doc (the 10 MD024
>   duplicate-heading findings match the IMPL-0001 precedent). Remaining
>   yamllint findings in `go/_defaults` predate this PR and are untouched.

#### Success Criteria

- Every Testing Plan item below is checked and reproducible from the PR
  description
- CI on the PR is green; blueprint lands as `go/k8s 0.1.0` in `registry.hcl`

---

## File Changes

| File                                                                                         | Action                         | Description                                                                                                                                                                          |
| -------------------------------------------------------------------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `go/k8s/blueprint.hcl`                                                                       | Rewrite                        | Variables, conditions, rename, defaults-exclude, hooks (Phase 2)                                                                                                                     |
| `go/k8s/charts/${project_name}/templates/*`                                                  | Delete 10 / template 8+helpers | Backends out; rest → `.tmpl` with `${project_name}.*` helpers (Phases 1, 3)                                                                                                          |
| `go/k8s/charts/${project_name}/tests/*`                                                      | Delete 3 / template 8          | Backend tests out; rest updated + `.tmpl` (Phases 1, 3)                                                                                                                              |
| `go/k8s/charts/${project_name}/{values.schema.json,ci/ci-values.yaml,README.md.gotmpl.tmpl}` | Modify                         | Schema scrub + template; generic CI values; docs scrub (Phase 3)                                                                                                                     |
| `go/k8s/helm.just` → `helm.just.tmpl`                                                        | Rewrite                        | Clean just module + k3d group + helm-plugins bootstrap (Phase 4)                                                                                                                     |
| `go/k8s/{ct.yaml,charts/.yamllint.yml.tmpl,mise.toml.tmpl,README.md.tmpl}`                   | Modify                         | Schema comment; var fix; tool pins; README scrub (Phases 2, 4)                                                                                                                       |
| `go/k8s/.github/workflows/`                                                                  | Restructure                    | `ci.yml` generalized; `release-ghcr.yml`/`release-ecr.yml` self-contained trains; `release.yml`, `ghcr.yml`, `ecr.yml`, `gh-pages.yml`, `changelog-update.yml` removed (Phases 1, 5) |
| `go/k8s/{Makefile,mise.toml}` + chart `README.md`/raw gotmpl                                 | Delete                         | Raw copies and generated artifacts (Phase 1)                                                                                                                                         |
| `go/k8s/docs/publishing-to-ecr.md`                                                           | Move + scrub                   | From chart `docs/`; ships only for ecr (Phases 1, 5)                                                                                                                                 |
| `go/_defaults/justfile.tmpl`                                                                 | Modify (OQ-3)                  | `import? 'docker.just'` / `import? 'helm.just'`                                                                                                                                      |
| `registry.hcl`                                                                               | Regenerate                     | `forge registry update` (Phase 6)                                                                                                                                                    |

## Testing Plan

Mirrors DESIGN-0004's Testing Strategy; executed in Phase 6 (earlier phases run
the relevant subset as success criteria):

- [x] `forge create go/k8s test-svc --defaults` + hooks clean (hooks caveat:
      forge v0.8 never executes post-create hooks — see Phase 6 notes)
- [x] `helm lint` / `helm template` (zero overrides) / `helm unittest` /
      `ct lint` pass
- [x] `helm-docs` clean when enabled
- [x] `docker buildx bake --print` resolves
- [x] `actionlint` clean on rendered workflows
- [x] Flag matrix: `container_registry=ecr`, `enable_monitoring=false`,
      `enable_helm_docs=false`
- [x] `grep -ri "repo-guardian\|donaldgifford/repo"` → zero hits
- [x] `/registry-validate` clean

## Open Questions

Each question lists my recommendation as **a.** with alternatives.

> **All questions resolved 2026-08-15.** Decisions: 1 = target forge v0.8 (see
> below), 2a, 3a, 4a, 5a. Phase tasks already assume these options; no open
> decision gates remain.

### 1. Variable syntax: forge v0.8 removes the legacy forms

**Decision: target forge v0.8** (2026-08-15, per issue #14; version naming:
installed = v0.7, IMPL-0009 release = v0.8).

The originally-drafted "dual-compatible" option assumed the legacy `validate`
regex attribute survives into the new release; issue #14 and forge's
MIGRATION.md confirm it does not — `choice`, `choices`, **and** `validate` are
all rejected at load time in v0.8. So go/k8s is written directly in v0.8 syntax:
bareword types, `validation { contains(...) }` for the
`license`/`container_registry` enums, `can(regex(...))` for the name checks,
`type = bool` for the enable flags (full sketch in DESIGN-0004). Consequences
recorded in the phases: forge v0.8 must be installed before Phase 2
verification, and the other blueprints stay on legacy syntax until the issue #14
sweep (out of scope here).

### 2. Inherited variable surface (Backstage / git-provider vars)

**Decision: a** — full inherited surface, GitHub-pinned defaults, Backstage
prompts kept, no `git_provider` prompt.

`go/_defaults` templates reference `project_org`, `git_host`,
`renovate_config_prefix`, and four required Backstage `project_component_*`
vars. The design's 8-variable prompt list would fail rendering them. go/docker
solves this with a `git_provider` (forgejo|github) choice driving conditional
defaults plus the four Backstage prompts. Note: issue #14 plans to collapse the
git-provider cluster into one `object({...})` variable registry-wide, but that
requires migrating the `_defaults` templates to attribute access
(`${git_provider.org}`) — until that sweep, go/k8s declares the flat scalars the
inherited templates reference today, and the object migration picks go/k8s up
with everything else.

- **a.** Declare the full inherited surface with GitHub-pinned defaults —
  `project_org` defaults to `${project_owner}`, `git_host` to `github.com`,
  `renovate_config_prefix` to `github` — keep the four Backstage prompts
  (catalog-info parity with go/docker), and skip the `git_provider` prompt
  entirely: the GHCR/ECR release stack (SLSA, GITHUB_TOKEN, GH OIDC) is
  GitHub-only, so offering forgejo would scaffold a broken release train.
  Recommended.
- **b.** Mirror go/docker exactly, `git_provider` prompt included, with
  `.github/` excluded for forgejo — maximal consistency, but a forgejo scaffold
  ships no working chart CI or release path.
- **c.** `defaults { exclude }` the files that need the extra vars
  (catalog-info.yaml.tmpl et al.) and keep the design's minimal 8-variable
  prompt surface — smallest interface, diverges from every other go blueprint's
  output.

### 3. How `helm.just` (and `docker.just`) join the main justfile

**Decision: a** — `import?` optional imports in `go/_defaults/justfile.tmpl`.

No current blueprint imports `docker.just`; `go/_defaults/justfile.tmpl` has no
import lines, so go/docker's module is reachable only via `just -f docker.just`.

- **a.** Add `import? 'docker.just'` + `import? 'helm.just'` (optional imports,
  just ≥ 1.33) to `go/_defaults/justfile.tmpl`. One shared edit; recipes appear
  in top-level `just --list` whenever the module file exists, and it's a no-op
  for go/std and every other blueprint — fixes go/docker's unwired module as a
  side effect. Recommended.
- **b.** Ship a go/k8s-level `justfile.tmpl` override with hard `import` lines —
  no shared-file change, but a full copy of the defaults justfile to keep in
  sync (the drift cost DESIGN-0002 work would inherit).
- **c.** Leave the modules standalone (`just -f helm.just helm-test`), matching
  go/docker today — zero changes, worst discoverability.

### 4. Inherited release/changelog workflow reconciliation

**Decision: a** — exclude inherited `release.yml` + `.goreleaser.yml.tmpl`;
delete seeded `changelog-update.yml`; inherit the default changelog pair.

`go/_defaults` ships a goreleaser `release.yml` (+ `.goreleaser.yml.tmpl`) that
collides with go/k8s's renamed `release.yml`, and a `changelog.yml` (PR drift
check) + `changelog-regen.yml` (push regen) pair overlapping the seeded
`changelog-update.yml` (push regen via PR, root changelog only).

- **a.** `defaults { exclude }` the inherited `release.yml` and
  `.goreleaser.yml.tmpl` (this blueprint releases an image + chart, not
  goreleaser binaries); delete the seeded `changelog-update.yml` and inherit the
  default changelog pair (chart changelog regen already happens inside the
  publish workflow's git-cliff step). Recommended.
- **b.** Keep goreleaser alongside the container train (rename one of the
  release workflows) — binary artifacts for a k8s service are usually dead
  weight; only pick this if you want `go install`-able releases too.
- **c.** Keep the seeded `changelog-update.yml` (PR-based regen) and exclude the
  inherited `changelog-regen.yml` instead — PR-based regen is tidier
  history-wise but diverges from every other go blueprint.

### 5. Workflow generalization: GitHub-context vs forge-templating

**Decision: a** — repo-agnostic workflows via GitHub context; files stay plain
`.yml`.

The seeded workflows hardcode `donaldgifford/repo-guardian` in env blocks, SLSA
image refs, and chart paths. Two ways to generalize. Note: GitHub's `${{ ... }}`
expression syntax collides with HCL2 (`${` starts interpolation), so
forge-templated workflows need every GitHub expression escaped as `$${{ ... }}`.

- **a.** Make the workflows repo-agnostic with GitHub context —
  `github.repository` for `IMAGE_REPO`, `github.repository_owner` for
  `CHART_NAMESPACE`, a `CHART_DIR=$(echo charts/*/)` resolution step for chart
  paths — and keep them plain `.yml` (copied verbatim, no forge vars). No
  escaping churn, `actionlint` runs against the registry source at rest, and the
  same files work for any owner/repo without re-scaffolding. Recommended.
- **b.** Convert to `.tmpl` and bake `${project_owner}/${project_name}` at
  scaffold time, escaping every GitHub expression as `$${{ ... }}`. Values are
  explicit in the output, but it's hundreds of escapes across the two release
  trains, the registry copies stop being lintable YAML, and any repo rename
  breaks the baked refs.

## Dependencies

- **forge v0.8** — required from Phase 2 on (the installed v0.7 binary, commit
  `585dddd`, cannot load `validation` blocks); build from forge main or install
  the v0.8 release. Phase 1 is version-independent.
- Local toolchain for Phase 4/6 verification: `helm`, `ct` (chart-testing),
  `helm-docs`, `helm-unittest` (helm plugin), `k3d`, `docker buildx`,
  `actionlint` — all mise-managed except the helm plugin
- All OQ decisions recorded (option **a** throughout, 2026-08-15) — the only
  remaining gate is the forge v0.8 install for Phase 2+
- No dependency on DESIGN-0002/0003 work (inheritance picks up whatever lands
  later)

## References

- [DESIGN-0004](../design/0004-gok8s-blueprint-go-service-with-helm-chart-and-registry-flagged.md)
  — the design this implements (decisions 1a–7a, 8b, 9a; blueprint.hcl sketch
  updated to v0.8 syntax)
- [forge-registry#14](https://github.com/donaldgifford/forge-registry/issues/14)
  — registry-wide migration to forge v0.8 variable syntax (and the later
  `object({...})` git-provider collapse); go/k8s lands on v0.8 first
- [forge MIGRATION.md — variable type system upgrade](https://github.com/donaldgifford/forge/blob/main/docs/MIGRATION.md#variable-type-system-upgrade-v07)
  — `choice`/`choices`/`validate` removal and the `validation` block forms
- Verified forge internals (repo `~/code/forge`): `internal/config/vartype.go`
  (choice removal, bool support), `internal/config/loader_hcl_helpers.go:122`
  (nil-context exclude eval), `internal/create/conditions.go` (source-relpath
  glob match), `internal/create/create.go:350` (rename interpolation + prefix
  match), `internal/defaults/resolver.go` (exact-relpath inheritance,
  `defaults.exclude`)
- [donaldgifford/repo-guardian](https://github.com/donaldgifford/repo-guardian)
  — seed source
- PR #10 (HCL2 template migration — `{{ }}` passthrough), PR #11
  (`${project_name}/` wrapper flatten)
- [helm-unittest](https://github.com/helm-unittest/helm-unittest),
  [chart-testing](https://github.com/helm/chart-testing),
  [helm-docs](https://github.com/norwoodj/helm-docs), [k3d](https://k3d.io),
  [just modules / optional imports](https://just.systems/man/en/imports.html)
- [IMPL-0001](./0001-forge-registry-skills-plugin.md) — phase/task format
  precedent
