# Changelog

All notable changes to this project are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/).

## [unreleased]

### Features

- Add forge-registry skill foundation and reference files (Phase 1)
- Add registry-list and registry-validate skills (Phase 2)
- Add blueprint-scaffold skill (Phase 3)
- Add mutation skills — update, add-template, bump-version (Phase 4)
- Add registry-review skill (Phase 5)
- Add rust defaults settings.json and update CLAUDE.md (Phase 6)
- *(go)* Add justfile, go/kubebuilder blueprint, docker integration, and cliff/release tooling ([#${2}](https://github.com/donaldgifford/forge-registry/issues/${2}))
- *(homelab)* Seed homelab/* category for IMPL-0005 monorepo split
- *(homelab)* Add homelab/go blueprint + flatten ${project_name}/ wrapper across registry ([#${2}](https://github.com/donaldgifford/forge-registry/issues/${2}))
- *(go)* Add go/k8s blueprint — Helm chart, k3d loop, registry-flagged release trains ([#${2}](https://github.com/donaldgifford/forge-registry/issues/${2}))
- *(go/cli)* Migrate blueprint to forge v0.8 variable syntax
- *(go/docker,std/new)* Migrate blueprints to forge v0.8 variable syntax
- *(bun/std)* Migrate blueprint to forge v0.8 variable syntax
- *(std/docs)* Migrate blueprint to forge v0.8 variable syntax
- *(homelab)* Migrate all 8 blueprints to forge v0.8 variable syntax
- *(go/ext,go/kubebuilder,rust)* Swap to forge v0.8 variable syntax
- *(rust)* Declare project_owner in rust/std and rust/esp32
- *(go/ext,go/kubebuilder,rust)* Declare GitHub-pinned provider scalars
- *(go/ext,go/kubebuilder,rust)* Declare required Backstage component vars
- *(go/ext,go/kubebuilder,rust)* Exclude inherited .forgejo tree; declare go_version
- *(go/kubebuilder)* Declare git init + go mod tidy post_create hooks
- *(go/std)* Rebuild blueprint on forge v0.8 scalar conventions
- [**breaking**] Collapse the git-provider scalar cluster into one object variable

### Bug Fixes

- Deps
- Resolve template variable mismatches and add missing YAML document start markers
- Complete v1→v2 template syntax migration ([#${2}](https://github.com/donaldgifford/forge-registry/issues/${2}))
- *(go)* Migrate justfile and cliff templates to HCL2 syntax ([#${2}](https://github.com/donaldgifford/forge-registry/issues/${2}))
- *(go/k8s)* Lockstep release train + fixes from first real-world use ([#${2}](https://github.com/donaldgifford/forge-registry/issues/${2}))

### Other

- Update ([#${2}](https://github.com/donaldgifford/forge-registry/issues/${2}))

### Documentation

- Add design doc and update docz indexes
- INV-0001 + IMPL-0003 — plan the registry-wide forge v0.8 migration ([#${2}](https://github.com/donaldgifford/forge-registry/issues/${2}))
- Refresh v0.8 variable conventions and add go/cli var-file example
- *(impl-0003)* Check off Phase 5 landing task — PR #19 open
- *(impl-0003)* Record Phase 6 findings — object shape validated, supply blocked
- *(impl-0003)* Record byte-diff regression evidence for Phase 1
- Close two verification gaps in Phase 2 and Phase 4 criteria
- *(impl-0003)* Record that the forge#42 fix is verified working
- *(impl-0003)* Link forge#43 as the fix for the Phase 7 blocker
- *(examples)* Move var-files to the git_provider object + add forgejo overlay
- Record the object migration in IMPL-0003 and CLAUDE.md

### Testing

- *(scripts)* Add scaffold-smoke.sh; verify all 19 blueprints green
- *(smoke)* Add object-supply and negative passes to scaffold-smoke.sh

### Miscellaneous Tasks

- Cleanup ([#${2}](https://github.com/donaldgifford/forge-registry/issues/${2}))
- *(docs)* Add examples/ with forge-vars.hcl var-file examples; refresh root README ([#${2}](https://github.com/donaldgifford/forge-registry/issues/${2}))
- *(homelab/go)* Align go_version with the go family default
- *(registry)* Bump all blueprints to 0.2.0 and sync registry.hcl
- *(registry)* Refresh commit pins and sync descriptions/tags
- *(blueprints)* Bump all 19 to 0.3.0 for the object migration
- *(registry)* Sync registry.hcl to the 0.3.0 object migration

