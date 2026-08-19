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
- *(go)* Add justfile, go/kubebuilder blueprint, docker integration, and cliff/release tooling ([#6](https://github.com/donaldgifford/forge-registry/issues/6))
- *(homelab)* Seed homelab/* category for IMPL-0005 monorepo split
- *(homelab)* Add homelab/go blueprint + flatten ${project_name}/ wrapper across registry ([#11](https://github.com/donaldgifford/forge-registry/issues/11))
- *(go)* Add go/k8s blueprint — Helm chart, k3d loop, registry-flagged release trains ([#15](https://github.com/donaldgifford/forge-registry/issues/15))
- Migrate all blueprints to forge v0.8 variable syntax (pass 1) ([#19](https://github.com/donaldgifford/forge-registry/issues/19))
- [**breaking**] Collapse the git-provider scalar cluster into one object variable

### Bug Fixes

- Deps
- Resolve template variable mismatches and add missing YAML document start markers
- Complete v1→v2 template syntax migration ([#8](https://github.com/donaldgifford/forge-registry/issues/8))
- *(go)* Migrate justfile and cliff templates to HCL2 syntax ([#10](https://github.com/donaldgifford/forge-registry/issues/10))
- *(go/k8s)* Lockstep release train + fixes from first real-world use ([#17](https://github.com/donaldgifford/forge-registry/issues/17))

### Other

- Update ([#12](https://github.com/donaldgifford/forge-registry/issues/12))

### Documentation

- Add design doc and update docz indexes
- INV-0001 + IMPL-0003 — plan the registry-wide forge v0.8 migration ([#18](https://github.com/donaldgifford/forge-registry/issues/18))
- *(examples)* Move var-files to the git_provider object + add forgejo overlay
- Record the object migration in IMPL-0003 and CLAUDE.md
- *(impl-0003)* Check off pass-1 merge and the pass-2 PR

### Testing

- *(smoke)* Add object-supply and negative passes to scaffold-smoke.sh

### Miscellaneous Tasks

- Cleanup ([#13](https://github.com/donaldgifford/forge-registry/issues/13))
- *(docs)* Add examples/ with forge-vars.hcl var-file examples; refresh root README ([#16](https://github.com/donaldgifford/forge-registry/issues/16))
- *(blueprints)* Bump all 19 to 0.3.0 for the object migration
- *(registry)* Sync registry.hcl to the 0.3.0 object migration
- *(registry)* Refresh latest_commit pins after rebase onto main
- Keep the donald-loop iteration counter out of the PR diff

