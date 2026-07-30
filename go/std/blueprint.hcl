name        = "go-std"
description = "Go Standard Repo"
version     = "0.1.0"
tags        = ["go-std"]

variable "project_name" {
  description = "Name of the project"
  type        = "string"
  required    = true
  validate    = "^[a-z][a-z0-9-]*$"
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

variable "backstage_tags" {
  description = "Backstage Component spec config"
  type        = "map"
  required    = true
}
