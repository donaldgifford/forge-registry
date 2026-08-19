# Forgejo overlay — retargets any multi-provider blueprint at
# git.fartlab.dev.
#
# Vars files compose left-to-right and later files win on key collision,
# so this carries only the provider delta:
#
#   forge create go/cli --registry-dir . \
#     --output-dir release-tool \
#     --var-file docs/examples/go-cli.forge-vars.hcl \
#     --var-file docs/examples/forgejo.forge-vars.hcl
#
# Applies to the 13 cluster blueprints (bun/std, go/cli, go/docker,
# std/docs, std/new, homelab/*). The GitHub-pinned blueprints — go/std,
# go/ext, go/k8s, go/kubebuilder, rust/std, rust/esp32 — accept the same
# key, but they ship no .forgejo/ tree, so only the derived attributes
# (org / host / renovate_config_prefix) take effect.
#
# All four attributes appear here because objects replace wholesale:
# forge has no `optional()` for exact object types, so a partial object
# is rejected with `attributes "host", "org", and
# "renovate_config_prefix" are required`. This is also why the old
# `--set git_provider=forgejo` shorthand no longer exists — one key,
# supplied in full, is the replacement.
#
# `name = "forgejo"` is what flips the tree: .forgejo/ ships and
# .github/ is excluded.
git_provider = {
  name                   = "forgejo"
  org                    = "homelab"
  host                   = "git.fartlab.dev"
  renovate_config_prefix = "git.fartlab.dev"
}
