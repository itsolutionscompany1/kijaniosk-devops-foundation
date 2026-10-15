terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "staging" {
  metadata {
    name = "kijani-staging"
    labels = {
      environment = "staging"
    }
  }
}

resource "kubernetes_namespace" "production" {
  metadata {
    name = "kijani-production"
    labels = {
      environment = "production"
    }
  }
}
