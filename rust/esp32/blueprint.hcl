name        = "rust-esp32"
description = "Rust ESP32 Repo"
version     = "0.1.0"
tags        = ["rust", "esp32"]

variable "project_name" {
  description = "Name of the project"
  type        = "string"
  required    = true
  validate    = "^[a-z][a-z0-9-]*$"
}

variable "project_description" {
  description = "Description of the project"
  type        = "string"
  required    = true
}

variable "license" {
  description = "License type"
  type        = "choice"
  choices     = ["MIT", "Apache-2.0", "BSD-3-Clause", "none"]
  default     = "Apache-2.0"
}

hooks {
  post_create = ["git init"]
}

