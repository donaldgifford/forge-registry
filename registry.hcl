name        = "forge-registry"
description = "Forge Registry"

blueprint "go/std" {
  path          = "go/std"
  description   = "Go Standard Repository"
  version       = "0.2.0"
  latest_commit = "61b40bf3c79636baf0cd4209ce7d7422c1313166"
}

blueprint "go/ext" {
  path          = "go/ext"
  description   = "Go Extended Repository"
  version       = "0.2.0"
  tags          = ["go", "extended", "makefile"]
  latest_commit = "7f47f03efb859e1f078e53f1609ac4e203f7b6ac"
}

blueprint "rust/std" {
  path          = "rust/std"
  description   = "Rust Standard Repo"
  version       = "0.2.0"
  tags          = ["rust", "std"]
  latest_commit = "7f47f03efb859e1f078e53f1609ac4e203f7b6ac"
}

blueprint "rust/esp32" {
  path          = "rust/esp32"
  description   = "Rust ESP32 Repo"
  version       = "0.2.0"
  tags          = ["rust", "esp32"]
  latest_commit = "7f47f03efb859e1f078e53f1609ac4e203f7b6ac"
}

blueprint "go/kubebuilder" {
  path          = "go/kubebuilder"
  description   = "Go Kubernetes operator blueprint (kubebuilder)"
  version       = "0.2.0"
  tags          = ["go", "kubebuilder", "operator", "kubernetes"]
  latest_commit = "8643b869970ab2fe0ba463d90386926b99c116b3"
}

blueprint "std/new" {
  path          = "std/new"
  description   = "new std"
  version       = "0.2.0"
  tags          = ["std", "new"]
  latest_commit = "8be5bae5019874983251ea7cd863cd7d13d19de7"
}

blueprint "homelab/k8s" {
  path          = "homelab/k8s"
  description   = "ArgoCD-managed Kubernetes manifests for the homelab cluster"
  version       = "0.2.0"
  tags          = ["homelab", "k8s", "kustomize", "argocd", "forgejo"]
  latest_commit = "dccc765881a433306c620d108d54f9012b778984"
}

blueprint "homelab/tf-modules" {
  path          = "homelab/tf-modules"
  description   = "Terraform modules for the homelab, semver-tagged for terragrunt consumers"
  version       = "0.2.0"
  tags          = ["homelab", "terraform", "modules", "forgejo"]
  latest_commit = "dccc765881a433306c620d108d54f9012b778984"
}

blueprint "homelab/tf-live" {
  path          = "homelab/tf-live"
  description   = "Terragrunt live config + boilerplate templates, plan/apply via Atlantis"
  version       = "0.2.0"
  tags          = ["homelab", "terraform", "terragrunt", "atlantis", "forgejo"]
  latest_commit = "dccc765881a433306c620d108d54f9012b778984"
}

blueprint "homelab/images" {
  path          = "homelab/images"
  description   = "Packer image builds for VMs and shared container images"
  version       = "0.2.0"
  tags          = ["homelab", "packer", "images", "forgejo"]
  latest_commit = "dccc765881a433306c620d108d54f9012b778984"
}

blueprint "homelab/charts" {
  path          = "homelab/charts"
  description   = "Helm charts published as OCI artifacts to Harbor + Forgejo Packages"
  version       = "0.2.0"
  tags          = ["homelab", "helm", "charts", "oci", "forgejo"]
  latest_commit = "dccc765881a433306c620d108d54f9012b778984"
}

blueprint "homelab/infra" {
  path          = "homelab/infra"
  description   = "Catch-all for non-IaC, non-k8s homelab config (talos, network, proxmox, servers)"
  version       = "0.2.0"
  tags          = ["homelab", "infra", "forgejo"]
  latest_commit = "dccc765881a433306c620d108d54f9012b778984"
}

blueprint "homelab/docs" {
  path          = "homelab/docs"
  description   = "Docusaurus site that aggregates docs from every homelab repo at build time"
  version       = "0.2.0"
  tags          = ["homelab", "docs", "docusaurus", "forgejo"]
  latest_commit = "dccc765881a433306c620d108d54f9012b778984"
}

blueprint "homelab/go" {
  path          = "homelab/go"
  description   = "Go project blueprint with homelab conventions (forgejo default, github mirror)"
  version       = "0.2.0"
  tags          = ["homelab", "go", "forgejo"]
  latest_commit = "efea98d436b6e0b73f1d675f435d9b6498a55334"
}

blueprint "go/docker" {
  path          = "go/docker"
  description   = "go docker blueprint"
  version       = "0.2.0"
  tags          = ["go", "docker"]
  latest_commit = "8be5bae5019874983251ea7cd863cd7d13d19de7"
}

blueprint "bun/std" {
  path          = "bun/std"
  description   = "bunjs typescript blueprint"
  version       = "0.2.0"
  tags          = ["bun", "typescript"]
  latest_commit = "cc7eedbd16840358d1d3c9b1cf145899fa0dfbc4"
}

blueprint "go/cli" {
  path          = "go/cli"
  description   = "go cli blueprint"
  version       = "0.2.0"
  tags          = ["go", "cli"]
  latest_commit = "a833a3ccc27265827fd724790534be4e07b75640"
}

blueprint "std/docs" {
  path          = "std/docs"
  description   = "docs repo blueprint"
  version       = "0.2.0"
  tags          = ["std", "docs"]
  latest_commit = "5a43daef6d2cf93d92070cf5f1aab9b17c5f723e"
}

blueprint "go/k8s" {
  path          = "go/k8s"
  description   = "Go service with container image + Helm chart, registry-flagged CI (GHCR/ECR)"
  version       = "0.2.0"
  tags          = ["go", "k8s", "helm", "docker"]
  latest_commit = "f010ca4a3f6ba6a98632edbd9866e895e0688206"
}
