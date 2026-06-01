name        = "forge-registry"
description = "Forge Registry"

blueprint "go-std" {
  path          = "go/std"
  description   = "Go Standard Repository"
  version       = "0.1.0"
  latest_commit = "fce647efc05a0e6d51d6927636d67f018a58c6ad"
}

blueprint "go/ext" {
  path          = "go/ext"
  description   = "Go Extended Repository"
  version       = "0.1.0"
  tags          = ["go", "extended", "makefile"]
  latest_commit = "233ae2fe1825a2405d50c05d07ff40cfa9d17f02"
}

blueprint "rust/std" {
  path          = "rust/std"
  description   = "Rust Standard Repo"
  version       = "0.1.0"
  tags          = ["rust", "std"]
  latest_commit = "518c7642d7e1f5e5ce74023f0c6a9b65bcd14871"
}

blueprint "rust/esp32" {
  path          = "rust/esp32"
  description   = "Rust ESP32 Repo"
  version       = "0.1.0"
  tags          = ["rust", "esp32"]
  latest_commit = "518c7642d7e1f5e5ce74023f0c6a9b65bcd14871"
}


blueprint "go-kubebuilder" {
  path          = "go/kubebuilder"
  description   = "Go Kubernetes operator blueprint (kubebuilder)"
  version       = "0.1.0"
  tags          = ["go", "kubebuilder", "operator", "kubernetes"]
  latest_commit = "233ae2fe1825a2405d50c05d07ff40cfa9d17f02"
}

blueprint "std/new" {
  path          = "std/new"
  description   = "new std"
  version       = "0.1.0"
  tags          = ["std", "new"]
  latest_commit = "233ae2fe1825a2405d50c05d07ff40cfa9d17f02"
}

blueprint "homelab/k8s" {
  path          = "homelab/k8s"
  description   = "ArgoCD-managed Kubernetes manifests for the homelab cluster"
  version       = "0.1.0"
  tags          = ["homelab", "k8s", "kustomize", "argocd", "forgejo"]
  latest_commit = "57996c5612f350b63d40cdeb5e6f531ecdc48b2d"
}

blueprint "homelab/tf-modules" {
  path          = "homelab/tf-modules"
  description   = "Terraform modules for the homelab, semver-tagged for terragrunt consumers"
  version       = "0.1.0"
  tags          = ["homelab", "terraform", "modules", "forgejo"]
  latest_commit = "57996c5612f350b63d40cdeb5e6f531ecdc48b2d"
}

blueprint "homelab/tf-live" {
  path          = "homelab/tf-live"
  description   = "Terragrunt live config + boilerplate templates, plan/apply via Atlantis"
  version       = "0.1.0"
  tags          = ["homelab", "terraform", "terragrunt", "atlantis", "forgejo"]
  latest_commit = "57996c5612f350b63d40cdeb5e6f531ecdc48b2d"
}

blueprint "homelab/images" {
  path          = "homelab/images"
  description   = "Packer image builds for VMs and shared container images"
  version       = "0.1.0"
  tags          = ["homelab", "packer", "images", "forgejo"]
  latest_commit = "57996c5612f350b63d40cdeb5e6f531ecdc48b2d"
}

blueprint "homelab/charts" {
  path          = "homelab/charts"
  description   = "Helm charts published as OCI artifacts to Harbor + Forgejo Packages"
  version       = "0.1.0"
  tags          = ["homelab", "helm", "charts", "oci", "forgejo"]
  latest_commit = "57996c5612f350b63d40cdeb5e6f531ecdc48b2d"
}

blueprint "homelab/infra" {
  path          = "homelab/infra"
  description   = "Catch-all for non-IaC, non-k8s homelab config (talos, network, proxmox, servers)"
  version       = "0.1.0"
  tags          = ["homelab", "infra", "forgejo"]
  latest_commit = "57996c5612f350b63d40cdeb5e6f531ecdc48b2d"
}

blueprint "homelab/docs" {
  path          = "homelab/docs"
  description   = "Docusaurus site that aggregates docs from every homelab repo at build time"
  version       = "0.1.0"
  tags          = ["homelab", "docs", "docusaurus", "forgejo"]
  latest_commit = "57996c5612f350b63d40cdeb5e6f531ecdc48b2d"
}

blueprint "homelab/go" {
  path        = "homelab/go"
  description = "Go project blueprint with homelab conventions (forgejo default, github mirror)"
  version     = "0.1.0"
  tags        = ["homelab", "go", "forgejo"]
}
