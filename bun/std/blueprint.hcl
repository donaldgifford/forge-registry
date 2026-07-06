name        = "bun-std"
description = "bunjs typescript blueprint"
version     = "0.1.0"
tags        = ["bun", "typescript"]

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

# condition {
#   when    = some_variable
#   exclude = ["optional-dir/"]
# }

hooks {
  post_create = ["git init"]
}

rename {
  entry {
    from = "${project_name}/"
    to   = "."
  }
}
