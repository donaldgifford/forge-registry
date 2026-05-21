name        = "std-new"
description = "Generic std blueprint with multi-provider (github / forgejo) support"
version     = "0.1.0"
tags        = ["std", "new"]

variable "project_name" {
  description = "Name of the project (lowercase, kebab-case)"
  type        = "string"
  required    = true
  validate    = "^[a-z][a-z0-9-]*$"
}

variable "project_description" {
  description = "One-line description of the project (used in catalog-info, READMEs)"
  type        = "string"
  default     = "TODO: Add a description"
}

variable "license" {
  description = "License type"
  type        = "choice"
  choices     = ["MIT", "Apache-2.0", "BSD-3-Clause", "none"]
  default     = "Apache-2.0"
}

# Single source of truth. project_org / git_host / renovate_config_prefix
# derive from this via lazy-evaluated conditional defaults — set git_provider
# once and the rest fall out.
variable "git_provider" {
  description = "Git provider this repo lives on"
  type        = "choice"
  choices     = ["github", "forgejo"]
  default     = "github"
}

variable "project_org" {
  description = "Org/user owning the repo (defaults derived from git_provider; override at prompt if needed)"
  type        = "string"
  default     = "${git_provider == "github" ? "donaldgifford" : "homelab"}"
}

variable "git_host" {
  description = "Hostname of the git provider (derived from git_provider)"
  type        = "string"
  default     = "${git_provider == "github" ? "github.com" : "git.fartlab.dev"}"
}

variable "renovate_config_prefix" {
  description = "Renovate `extends:` source prefix (derived from git_provider)"
  type        = "string"
  default     = "${git_provider == "github" ? "github" : "git.fartlab.dev"}"
}

# Drop the provider-irrelevant directory from the scaffold output.
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

rename {
  entry {
    from = "${project_name}/"
    to   = "."
  }
}
