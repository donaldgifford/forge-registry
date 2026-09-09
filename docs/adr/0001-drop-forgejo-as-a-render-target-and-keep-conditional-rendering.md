---
id: ADR-0001
title: "Drop Forgejo as a render target and keep conditional rendering"
status: Accepted
author: Donald Gifford
created: 2026-09-09
---

<!-- markdownlint-disable-file MD025 MD041 -->

# ADR-0001: Drop Forgejo as a render target and keep conditional rendering

<!--toc:start-->

- [Summary](#summary)
- [Context](#context)
- [Decision](#decision)
  - [Supporting Data](#supporting-data)
- [Consequences](#consequences)
  - [Positive](#positive)
  - [Negative](#negative)
  - [Neutral](#neutral)
- [Alternatives Considered](#alternatives-considered)
- [References](#references)

<!--toc:end-->

## Summary

The registry stops shipping anything Forgejo-specific: the `.forgejo/` trees,
the `condition` blocks keyed on `git_provider.name`, the `forgejo` enum value,
the overlay example, and the smoke-test coverage for it. The `git_provider`
object keeps its shape, and conditional rendering stays in daily use through
`go/k8s`, so nothing about forge's ability to render on a variable changes. The
homelab category is kept and retargeted at GitHub. This supersedes the decision
in INV-0001 OQ-2 to keep Forgejo shippable "for when it returns".

## Context

The Forgejo instance the registry was built around (`git.fartlab.dev`) is gone.
INV-0001 recorded that on 2026-08-17 and chose, in OQ-2 (a), to flip the default
to GitHub but leave the Forgejo templates and enum value in place. A month later
the cost of that choice is visible across the whole tree:

- Every one of the 19 blueprints carries Forgejo plumbing. Thirteen ship both a
  `.github/` and a `.forgejo/` tree and pick one with a pair of `condition`
  blocks. The other six carry a nine-entry exclude list whose only purpose is to
  drop the `.forgejo/` tree the registry root ships. All 19 validate
  `git_provider.name` against `["forgejo", "github"]`.
- INV-0003 found Forgejo prose leaking into the GitHub-pinned go category:
  `go/_defaults/CLAUDE.md.tmpl` tells every forged go repo it "Lives on
  Forgejo", and the same file documents `GITEA_TOKEN` release steps.
- The homelab category is Forgejo-shaped end to end: descriptions, tags, and
  about 45 lines of prose across 12 files naming Forgejo, Harbor, or
  `fartlab.dev`, including workflows such as `chart-publish.yml` that were never
  written.
- `scripts/scaffold-smoke.sh` spends a whole section scaffolding the
  multi-provider blueprints with a Forgejo object to assert the `.forgejo/` tree
  appears.

The one requirement raised against removal was that the registry must keep the
ability to render templates differently depending on a variable such as the git
provider. That ability belongs to forge, not the registry; the registry can only
exercise it, and the survey below shows it is exercised by `go/k8s` on variables
that have nothing to do with Forgejo.

## Decision

1. **Remove every Forgejo-specific artifact.** The `_defaults/.forgejo/`,
   `homelab/_defaults/.forgejo/`, and `homelab/go/.forgejo/` trees; the
   `git_provider.name` `condition` blocks in the 13 multi-provider blueprints;
   the `.forgejo/…` exclude lists in the six GitHub-pinned blueprints; the
   `forgejo` value and error message in every validation; the overlay comments
   in `blueprint.hcl`; `docs/examples/forgejo.forge-vars.hcl` and its README
   row; the Forgejo comments in the other example var files; the three
   `.dockerignore` lines; and the Forgejo prose in `go/_defaults`, `std/docs`,
   and homelab.
2. **Keep the `git_provider` object shape unchanged**:
   `object({ name, org, host, renovate_config_prefix })` in all 19 blueprints.
   Objects replace wholesale, so changing the type would break every consumer's
   var file and `.forge-lock.hcl`. The validation narrows to
   `contains(["github"], var.git_provider.name)`. A new provider value is added
   only together with the tree and `condition` blocks that make it real; an enum
   value with nothing behind it scaffolds a repo with no CI.
3. **Keep conditional rendering exercised.** `go/k8s` already uses all three
   forms on non-provider variables (see Supporting Data) and continues to.
   Templates keep referencing `${git_provider.host}` and `${git_provider.org}`
   rather than literal `github.com`, which is also what forge-registry#28 asks
   for.
4. **Port the issue forms and PR template; do not delete them.** The registry
   root ships no GitHub issue or PR templates today; only `go/k8s` and
   `rust/_defaults` do. Forgejo issue forms use GitHub's issue-form schema, so
   the six files move to `_defaults/.github/ISSUE_TEMPLATE/` as they are. The
   `PULL_REQUEST_TEMPLATE.yml` converts to Markdown because GitHub only reads
   Markdown there. `labels-sync.yml.tmpl` is a TODO stub and is deleted.
   `lint.yml.tmpl` is deleted once `_defaults/.github/workflows/ci.yml` is
   confirmed to cover the same checks.
5. **Keep the homelab category and retarget it at GitHub.** All eight blueprints
   stay. Their `.github/` workflow twins already exist, so the work is deleting
   the `.forgejo/` twins, dropping `forgejo` from tags and descriptions,
   rewriting the prose, and deleting references to workflows that were never
   written rather than rewriting them.
6. **Sequence it after IMPL-0004 and before the INV-0003 fix PRs.** Every
   blueprint version bumps, so the removal lands as one PR once the bump gate
   and release flow exist. The INV-0003 fixes then apply to a tree with less in
   it.
7. **`scripts/scaffold-smoke.sh` loses its Forgejo coverage**: the
   `is_multi_provider` helper, the Forgejo object, the "object supply (forgejo)"
   section, and the two expectations on the old error message. `registry.hcl` is
   regenerated with `forge registry update`.

### Supporting Data

Forgejo footprint at registry commit `2c186e4`, from a `git grep` survey on
2026-09-09:

| Where                                                 | What                                                                                                              |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `_defaults/.forgejo/`                                 | 9 files: 6 issue forms, a PR template, `lint` and `labels-sync` workflow templates                                |
| `homelab/_defaults/.forgejo/`, `homelab/go/.forgejo/` | 4 workflow templates, each with a `.github/` twin already present                                                 |
| 13 multi-provider `blueprint.hcl`                     | paired `condition` blocks excluding `.github/` or `.forgejo/`, plus overlay comments                              |
| 6 GitHub-pinned `blueprint.hcl`                       | a 9-entry `.forgejo/…` exclude list                                                                               |
| all 19 `blueprint.hcl`                                | `contains(["forgejo", "github"], var.git_provider.name)`                                                          |
| prose outside homelab                                 | `go/_defaults/{CLAUDE.md,README.md,.goreleaser.yml}.tmpl`, `std/docs/CLAUDE.md.tmpl`, three `.dockerignore` lines |
| `docs/examples`                                       | `forgejo.forge-vars.hcl`, its README row, comments in `go-cli` and `go-k8s` var files                             |
| `scripts/scaffold-smoke.sh`                           | `is_multi_provider`, `FORGEJO_OBJECT`, the Forgejo scaffold section, two error strings                            |
| homelab prose                                         | about 45 lines in 12 files; descriptions and tags in all 8 `blueprint.hcl`                                        |

Conditional rendering that does not depend on Forgejo, all in `go/k8s`:

| Form                      | Where                                                                                                                      | Keyed on                                                                 |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `condition { when … }`    | `blueprint.hcl:137-148,163,173,178`                                                                                        | `container_registry`, `enable_monitoring`, `enable_helm_docs`, `license` |
| `rename` on a variable    | `blueprint.hcl:150-155` (`release-${container_registry}.yml` becomes `release.yml`)                                        | `container_registry`                                                     |
| `%{ if … ~}` in templates | `README.md.tmpl:62-68`, `helm.just.tmpl:10-79`, `LICENSE.tmpl:1-256`, `charts/${project_name}/README.md.gotmpl.tmpl:11-26` | `container_registry`, `enable_helm_docs`, `license`                      |

The multi-provider blueprints are `bun/std`, `go/cli`, `go/docker`, all eight
`homelab/*`, `std/docs`, and `std/new`. The GitHub-pinned ones are `go/ext`,
`go/k8s`, `go/kubebuilder`, `go/std`, `rust/esp32`, and `rust/std`. After this
change the distinction no longer exists.

## Consequences

### Positive

- Thirteen blueprints lose two `condition` blocks each and six lose a nine-entry
  exclude list. The multi-provider versus GitHub-pinned distinction disappears,
  along with the smoke-test helper that detects it.
- The registry root gains GitHub issue forms it never had.
- The INV-0003 fix PRs shrink: the "Lives on Forgejo" finding and the
  `GITEA_TOKEN` release notes in `go/_defaults/CLAUDE.md.tmpl` go away here.
- One fewer place for provider-specific text to leak into forged repos.

### Negative

- Forgejo support is gone. Bringing it back means a new `.forgejo/` tree, the
  `condition` blocks, the enum value, and smoke coverage: this change in
  reverse.
- All 19 blueprint versions bump in one PR, and every consumer's next
  `forge sync` sees a registry-wide change.
- The homelab prose rewrite is manual work across 12 files.

### Neutral

- Consumers' `.forge-lock.hcl` inputs are unaffected because the object shape is
  unchanged. Var files with `name = "github"` keep working. A var file with
  `name = "forgejo"` fails validation with a clear message instead of
  scaffolding a repo whose CI targets a host that no longer exists.
- `renovate_config_prefix` is a constant `github` until a second provider
  exists. It stays in the object so that provider can set it without a type
  change.
- The registry-side rule matches the forge-side one in forge#44: GitHub is the
  default, other hosts are tracked but not supported until real templates exist.

## Alternatives Considered

- **Delete the homelab category.** Cleanest, and it would take most of the
  Forgejo footprint with it, but it drops 8 of 19 blueprints. Rejected because
  the blueprints are still wanted and their `.github/` workflow twins already
  exist, so retargeting is prose work.
- **Leave homelab as the one Forgejo-shaped category.** The root `.forgejo/`
  tree would move under `homelab/_defaults/` instead of going away. Rejected
  because it preserves the exact split this ADR removes.
- **Keep `forgejo` in the validation enum with no tree behind it.** Rejected for
  the reason INV-0001 OQ-2 already gave: an enum value with no tree scaffolds a
  repo with no CI.
- **Drop `renovate_config_prefix` from the object now that it is constant.**
  Rejected because objects replace wholesale, so the type change would break
  every consumer's var file and lock for no functional gain.

## References

- INV-0001 OQ-2, the decision this ADR supersedes:
  `docs/investigation/0001-migrate-remaining-blueprints-to-forge-v08-variable-syntax-and.md`
- INV-0003 addendum (blast radius, sequencing, the Forgejo line in the go
  category):
  `docs/investigation/0003-forge-go-k8s-scaffold-audit-before-initial-commit.md`
- IMPL-0004, which must land first:
  `docs/impl/0004-registry-release-automation-pr-semver-tag-version-gate-and.md`
- [forge-registry#28](https://github.com/donaldgifford/forge-registry/issues/28),
  the scaffold-audit tracking issue whose item 1 also requires
  `${git_provider.host}` over literal hosts
- [forge#44](https://github.com/donaldgifford/forge/issues/44), the forge-side
  default-host and `--git-host-type` design this mirrors
- `CLAUDE.md`, "`git_provider` is an object" and "Objects replace wholesale"
