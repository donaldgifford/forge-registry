name        = "homelab-charts"
description = "Helm charts published as OCI artifacts to Harbor + Forgejo Packages"
version     = "0.1.0"
tags        = ["homelab", "helm", "charts", "oci", "forgejo"]

variable "project_name" {
  description = "Name of the project (lowercase, kebab-case)"
  type        = "string"
  required    = true
  validate    = "^[a-z][a-z0-9-]*$"
}

variable "project_description" {
  description = "One-line description of the project"
  type        = "string"
  default     = "TODO: Add a description"
}

variable "license" {
  description = "License type"
  type        = "choice"
  choices     = ["MIT", "Apache-2.0", "BSD-3-Clause", "none"]
  default     = "Apache-2.0"
}

variable "git_provider" {
  description = "Git provider this repo lives on"
  type        = "choice"
  choices     = ["forgejo", "github"]
  default     = "forgejo"
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

hooks {
  post_create = ["git init"]
}

