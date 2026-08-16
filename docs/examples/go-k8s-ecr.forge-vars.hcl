# go/k8s — ECR overlay.
#
# Vars files compose left-to-right: later files override earlier ones
# on key collision, so this file only carries the delta on top of the
# base example:
#
#   forge create go/k8s --registry-dir . \
#     --output-dir payments-api \
#     --var-file docs/examples/go-k8s.forge-vars.hcl \
#     --var-file docs/examples/go-k8s-ecr.forge-vars.hcl

# Lands the self-contained ECR release train (aws-auth OIDC +
# ECR_PUBLISH_ENABLED arming gate) as .github/workflows/release.yml and
# ships docs/publishing-to-ecr.md with the one-time AWS setup.
container_registry = "ecr"
