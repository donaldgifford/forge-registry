name        = "go-docker"
description = "go docker blueprint"
version     = "0.2.0"
tags        = ["go", "docker"]

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

# Single source of truth — drives project_org / git_host / renovate_config_prefix.
variable "git_provider" {
  description = "Git provider this repo lives on"
  type        = string
  default     = "github"

  validation {
    condition     = contains(["forgejo", "github"], var.git_provider)
    error_message = "git_provider must be one of: forgejo, github."
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

variable "project_org" {
  description = "Org/user owning the repo"
  type        = string
  default     = "${git_provider == "forgejo" ? "homelab" : "donaldgifford"}"
}

variable "git_host" {
  description = "Hostname of the git provider"
  type        = string
  default     = "${git_provider == "forgejo" ? "git.fartlab.dev" : "github.com"}"
}

variable "renovate_config_prefix" {
  description = "Renovate `extends:` source prefix"
  type        = string
  default     = "${git_provider == "forgejo" ? "git.fartlab.dev" : "github"}"
}

condition {
  when    = git_provider != "github"
  exclude = [".github/"]
}

condition {
  when    = git_provider != "forgejo"
  exclude = [".forgejo/"]
}
