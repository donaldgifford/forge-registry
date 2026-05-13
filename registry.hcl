name        = "forge-registry"
description = "Forge Registry"

blueprint "go-std" {
  path          = "go/std"
  description   = "Go Standard Repository"
  version       = "0.1.0"
  latest_commit = "19e1e7331d07bd64ff72f56994c9ed131f112b18"
}

blueprint "go/ext" {
  path          = "go/ext"
  description   = "Go Extended Repository"
  version       = "0.1.0"
  tags          = ["go", "extended", "makefile"]
  latest_commit = "d8b0ffda5c9a5cf053ca987c6ecd9f013a2dcc6c"
}

blueprint "rust/std" {
  path          = "rust/std"
  description   = "Rust Standard Repo"
  version       = "0.1.0"
  tags          = ["rust", "std"]
  latest_commit = "19e1e7331d07bd64ff72f56994c9ed131f112b18"
}

blueprint "rust/esp32" {
  path          = "rust/esp32"
  description   = "Rust ESP32 Repo"
  version       = "0.1.0"
  tags          = ["rust", "esp32"]
  latest_commit = "19e1e7331d07bd64ff72f56994c9ed131f112b18"
}

blueprint "std" {
  path          = "std"
  description   = "TODO: Add a description"
  version       = "0.1.0"
  latest_commit = "19e1e7331d07bd64ff72f56994c9ed131f112b18"
}

blueprint "go-kubebuilder" {
  path        = "go/kubebuilder"
  description = "Go Kubernetes operator blueprint (kubebuilder)"
  version     = "0.1.0"
  tags        = ["go", "kubebuilder", "operator", "kubernetes"]
}
