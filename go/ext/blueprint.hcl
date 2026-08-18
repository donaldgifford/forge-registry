name        = "go-ext"
description = "Go extended blueprint"
version     = "0.1.0"
tags        = ["go", "extended"]

# forge v0.8 variable syntax (IMPL-0003): bareword types + `validation`
# blocks. The legacy choice/choices/validate forms are rejected at load
# time from v0.8 on.

variable "project_name" {
  description = "Name of the project"
  type        = string
  required    = true

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "project_name must be lowercase kebab-case (letters, digits, hyphens; starts with a letter)."
  }
}

variable "project_owner" {
  description = "Owner of the project"
  type        = string
  required    = true

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_owner))
    error_message = "project_owner must be lowercase kebab-case (letters, digits, hyphens; starts with a letter)."
  }
}

variable "project_description" {
  description = "Description of the project"
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
  default     = "1.26.4"
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

# ─── Inherited _defaults template surface ────────────────────────────
# This blueprint is GitHub-pinned: no git_provider prompt, so the vars
# the inherited renovate/catalog/CONTRIBUTING templates reference are
# declared with GitHub defaults (same pattern as go/k8s, IMPL-0003
# OQ-3a). The registry-root .forgejo/ tree is excluded below.

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

defaults {
  exclude = [
    ".forgejo/PULL_REQUEST_TEMPLATE.yml",
    ".forgejo/workflows/lint.yml.tmpl",
    ".forgejo/workflows/labels-sync.yml.tmpl",
    ".forgejo/ISSUE_TEMPLATE/bug.yml",
    ".forgejo/ISSUE_TEMPLATE/config.yml",
    ".forgejo/ISSUE_TEMPLATE/documentation.yml",
    ".forgejo/ISSUE_TEMPLATE/feature-core.yml",
    ".forgejo/ISSUE_TEMPLATE/feature-plugin.yml",
    ".forgejo/ISSUE_TEMPLATE/refactor.yml",
  ]
}
