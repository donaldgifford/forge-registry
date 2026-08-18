name        = "rust-esp32"
description = "Rust ESP32 Repo"
version     = "0.1.0"
tags        = ["rust", "esp32"]

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

hooks {
  post_create = ["git init"]
}

