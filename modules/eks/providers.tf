# modules/eks/providers.tf
# The kubernetes provider is configured in each environment's providers.tf
# using the cluster outputs. This file declares the requirement only.

terraform {
  required_providers {
    aws        = { source = "hashicorp/aws";        version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes"; version = "~> 2.0" }
    tls        = { source = "hashicorp/tls";        version = "~> 4.0" }
  }
}
