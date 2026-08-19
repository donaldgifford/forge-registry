name        = "std-new"
description = "Generic std blueprint with multi-provider (github / forgejo) support"
version     = "0.3.0"
tags        = ["std", "new"]

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

# Single source of truth for the provider and everything derived from it
# (issue #14). Objects replace wholesale — forge has no `optional()` for
# exact object types — so supplying this variable means supplying all
# four attributes. The forgejo variant ships as
# docs/examples/forgejo.forge-vars.hcl.
variable "git_provider" {
  description = "Git provider this repo lives on, and the values derived from it"
  type = object({
    name                   = string
    org                    = string
    host                   = string
    renovate_config_prefix = string
  })
  default = {
    name                   = "github"
    org                    = "donaldgifford"
    host                   = "github.com"
    renovate_config_prefix = "github"
  }

  validation {
    condition     = contains(["forgejo", "github"], var.git_provider.name)
    error_message = "git_provider.name must be one of: forgejo, github."
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

condition {
  when    = git_provider.name != "github"
  exclude = [".github/"]
}

condition {
  when    = git_provider.name != "forgejo"
  exclude = [".forgejo/"]
}
