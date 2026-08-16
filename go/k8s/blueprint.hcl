name        = "go-k8s"
description = "Go service with container image + Helm chart, registry-flagged CI (GHCR/ECR)"
version     = "0.1.0"
tags        = ["go", "k8s", "helm", "docker"]

# forge v0.8 variable syntax (IMPL-0009): bareword types + `validation`
# blocks. The legacy choice/choices/validate forms are rejected at load
# time from v0.8 on. This is the first v0.8-syntax blueprint in the
# registry; the rest migrate via forge-registry#14.

variable "project_name" {
  description = "Name of the project (lowercase, kebab-case)"
  type        = string
  required    = true

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "project_name must be lowercase kebab-case (letters, digits, hyphens; starts with a letter)."
  }
}

variable "project_owner" {
  description = "Owner of the project (user or org)"
  type        = string
  required    = true

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_owner))
    error_message = "project_owner must be lowercase kebab-case (letters, digits, hyphens; starts with a letter)."
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
  description = "Go toolchain version (matches go.mod, mise.toml, Dockerfile)"
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

# ─── Inherited go/_defaults template surface ─────────────────────────
# The GHCR/ECR release stack (SLSA, GITHUB_TOKEN, GH OIDC) is
# GitHub-only, so there is no git_provider prompt — the derived vars
# are pinned to GitHub defaults (IMPL-0002 OQ-2).

variable "project_org" {
  description = "Org/user owning the repo"
  type        = string
  default     = "${project_owner}"
}

variable "git_host" {
  description = "Hostname of the git provider"
  type        = string
  default     = "github.com"
}

variable "renovate_config_prefix" {
  description = "Renovate `extends:` source prefix"
  type        = string
  default     = "github"
}

variable "project_component_type" {
  description = "Backstage Entity Component Type"
  type        = string
  required    = true
}

variable "project_component_system" {
  description = "Backstage Entity Component reference System"
  type        = string
  required    = true
}

variable "project_component_lifecycle" {
  description = "Backstage Entity Component lifecycle"
  type        = string
  required    = true
}

variable "project_component_owner" {
  description = "Backstage Entity Component Owner"
  type        = string
  required    = true
}

# ─── Registry selection (IMPL-0002 OQ-5: one self-contained release
# train per registry; the winner renders as release.yml) ─────────────

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

rename {
  entry {
    from = ".github/workflows/release-${container_registry}.yml"
    to   = ".github/workflows/release.yml"
  }
}

# ─── Feature flags ───────────────────────────────────────────────────
# Exclude patterns match SOURCE paths (literal `${project_name}` dir;
# `$${...}` emits the literal). The trailing `*` covers both the
# pre-templating names and the `.tmpl` variants Phase 3 introduces.

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

# ─── Inherited files this blueprint replaces ─────────────────────────
# go/_defaults ships a goreleaser release train; go/k8s releases an
# image + chart instead (IMPL-0002 OQ-4). Exact relpaths — no globs.

defaults {
  exclude = [
    ".github/workflows/release.yml",
    ".goreleaser.yml.tmpl",
  ]
}

hooks {
  post_create = [
    "git init",
    "go mod tidy",
  ]
}
