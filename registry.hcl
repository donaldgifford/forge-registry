name        = "forge-registry"
description = "Forge Registry"

blueprint "go/std" {
  path          = "go/std"
  description   = "Go Standard Repo"
  version       = "0.3.0"
  tags          = ["go", "std"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "go/ext" {
  path          = "go/ext"
  description   = "Go extended blueprint"
  version       = "0.3.0"
  tags          = ["go", "extended"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "rust/std" {
  path          = "rust/std"
  description   = "Rust Standard Repo"
  version       = "0.3.0"
  tags          = ["rust", "std"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "rust/esp32" {
  path          = "rust/esp32"
  description   = "Rust ESP32 Repo"
  version       = "0.3.0"
  tags          = ["rust", "esp32"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "go/kubebuilder" {
  path          = "go/kubebuilder"
  description   = "Go Kubernetes operator blueprint (kubebuilder)"
  version       = "0.3.0"
  tags          = ["go", "kubebuilder", "operator", "kubernetes"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "std/new" {
  path          = "std/new"
  description   = "Generic std blueprint with multi-provider (github / forgejo) support"
  version       = "0.3.0"
  tags          = ["std", "new"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "homelab/k8s" {
  path          = "homelab/k8s"
  description   = "ArgoCD-managed Kubernetes manifests for the homelab cluster"
  version       = "0.3.0"
  tags          = ["homelab", "k8s", "kustomize", "argocd", "forgejo"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "homelab/tf-modules" {
  path          = "homelab/tf-modules"
  description   = "Terraform modules for the homelab, semver-tagged for terragrunt consumers"
  version       = "0.3.0"
  tags          = ["homelab", "terraform", "modules", "forgejo"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "homelab/tf-live" {
  path          = "homelab/tf-live"
  description   = "Terragrunt live config + boilerplate templates, plan/apply via Atlantis"
  version       = "0.3.0"
  tags          = ["homelab", "terraform", "terragrunt", "atlantis", "forgejo"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "homelab/images" {
  path          = "homelab/images"
  description   = "Packer image builds for VMs and shared container images"
  version       = "0.3.0"
  tags          = ["homelab", "packer", "images", "forgejo"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "homelab/charts" {
  path          = "homelab/charts"
  description   = "Helm charts published as OCI artifacts to Harbor + Forgejo Packages"
  version       = "0.3.0"
  tags          = ["homelab", "helm", "charts", "oci", "forgejo"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "homelab/infra" {
  path          = "homelab/infra"
  description   = "Catch-all for non-IaC, non-k8s homelab config (talos, network, proxmox, servers)"
  version       = "0.3.0"
  tags          = ["homelab", "infra", "forgejo"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "homelab/docs" {
  path          = "homelab/docs"
  description   = "Docusaurus site that aggregates docs from every homelab repo at build time"
  version       = "0.3.0"
  tags          = ["homelab", "docs", "docusaurus", "forgejo"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "homelab/go" {
  path          = "homelab/go"
  description   = "Go project blueprint with homelab conventions (forgejo default, github for mirror)"
  version       = "0.3.0"
  tags          = ["homelab", "go", "forgejo"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "go/docker" {
  path          = "go/docker"
  description   = "go docker blueprint"
  version       = "0.3.0"
  tags          = ["go", "docker"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "bun/std" {
  path          = "bun/std"
  description   = "bunjs typescript blueprint"
  version       = "0.3.0"
  tags          = ["bun", "typescript"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "go/cli" {
  path          = "go/cli"
  description   = "go cli blueprint"
  version       = "0.3.0"
  tags          = ["go", "cli"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "std/docs" {
  path          = "std/docs"
  description   = "docs repo blueprint"
  version       = "0.3.0"
  tags          = ["std", "docs"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}

blueprint "go/k8s" {
  path          = "go/k8s"
  description   = "Go service with container image + Helm chart, registry-flagged CI (GHCR/ECR)"
  version       = "0.3.0"
  tags          = ["go", "k8s", "helm", "docker"]
  latest_commit = "282ac5ca03bdd7a8cb4ca41cc281f33b0ba65199"
}
