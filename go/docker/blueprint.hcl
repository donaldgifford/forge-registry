name        = "go-docker"
description = "go docker blueprint"
version     = "0.1.0"
tags        = ["go", "docker"]

variable "project_name" {
  description = "Name of the project"
  type        = "string"
  required    = true
  validate    = "^[a-z][a-z0-9-]*$"
}

variable "license" {
  description = "License type"
  type        = "choice"
  choices     = ["MIT", "Apache-2.0", "BSD-3-Clause", "none"]
  default     = "Apache-2.0"
}

variable "go_version" {
  description = "Go toolchain version (matches go.mod, mise.toml, Dockerfile)"
  type        = "string"
  default     = "1.26.4"
}

# Single source of truth — drives project_org / git_host / renovate_config_prefix.
variable "git_provider" {
  description = "Git provider this repo lives on"
  type        = "choice"
  choices     = ["forgejo", "github"]
  default     = "forgejo"
}

variable "project_owner" {
  description = "Owner of the project"
  type        = "string"
  required    = true
  validate    = "^[a-z][a-z0-9-]*$"
}

variable "project_description" {
  description = "Description of the project"
  type        = "string"
  required    = true
}

variable "project_system" {
  description = "Backstage Component system"
  type        = "string"
  required    = true
}

variable "project_lifecycle" {
  description = "Backstage Component lifecycle"
  type        = "string"
  required    = true
}

variable "project_owner" {
  description = "Backstage Component Owner"
  type        = "string"
  required    = true
}

variable "project_service" {
  description = "Backstage Component Service"
  type        = "string"
  required    = true
}

variable "project_org" {
  description = "Org/user owning the repo"
  type        = "string"
  default     = "${git_provider == "forgejo" ? "homelab" : "donaldgifford"}"
}

variable "git_host" {
  description = "Hostname of the git provider"
  type        = "string"
  default     = "${git_provider == "forgejo" ? "git.fartlab.dev" : "github.com"}"
}

variable "renovate_config_prefix" {
  description = "Renovate `extends:` source prefix"
  type        = "string"
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

# variable "backstage_tags" {
#   description = "Backstage Component spec config"
#   type        = "map"
#   required    = true
# }
