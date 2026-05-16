# environments/dev/main.tf
# ---------------------------------------------------------------------------
# Dev environment — cost-optimised, public API endpoint allowed,
# single NAT gateway, smaller nodes, no deletion protection.
# ---------------------------------------------------------------------------

locals {
  environment  = "dev"
  cluster_name = "hiive-${local.environment}"
  region       = "us-east-1"

  common_tags = {
    Environment = local.environment
    Project     = "hiive"
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  cluster_name       = local.cluster_name
  region             = local.region
  vpc_cidr           = "10.10.0.0/16"
  single_nat_gateway = true   # Single NAT — cheaper for dev
  tags               = local.common_tags
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  cluster_name        = local.cluster_name
  environment         = local.environment
  kubernetes_version  = "1.29"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids

  # Dev: allow public API access so engineers can use kubectl without VPN
  endpoint_public_access = true
  api_allowed_cidrs      = ["0.0.0.0/0"]   # Restrict to your office CIDRs in practice

  node_instance_type = "t3.medium"
  node_capacity_type = "SPOT"   # Spot saves ~70% in dev; interruptions are acceptable
  node_desired       = 2
  node_min           = 1
  node_max           = 3

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller
# ---------------------------------------------------------------------------
module "alb_controller" {
  source = "../../modules/alb-controller"

  cluster_name      = module.eks.cluster_name
  vpc_id            = module.vpc.vpc_id
  region            = local.region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  replica_count     = 1   # Single replica is fine for dev
  tags              = local.common_tags
}

# ---------------------------------------------------------------------------
# Hello-world sample app (Kubernetes manifests managed in Terraform)
# ---------------------------------------------------------------------------
resource "kubernetes_namespace" "hiive" {
  metadata {
    name   = "hiive"
    labels = { environment = local.environment }
  }
}

resource "kubernetes_deployment_v1" "hello" {
  metadata {
    name      = "hello-world"
    namespace = kubernetes_namespace.hiive.metadata[0].name
    labels    = { app = "hello-world" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "hello-world" }
    }

    template {
      metadata {
        labels = { app = "hello-world" }
      }

      spec {
        container {
          name  = "hello"
          image = "public.ecr.aws/docker/library/nginx:stable-alpine"

          port {
            container_port = 80
          }

          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { cpu = "200m", memory = "128Mi" }
          }

          liveness_probe {
            http_get { path = "/"; port = 80 }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "hello" {
  metadata {
    name      = "hello-world"
    namespace = kubernetes_namespace.hiive.metadata[0].name
  }

  spec {
    selector = { app = "hello-world" }
    port {
      port        = 80
      target_port = 80
    }
    type = "ClusterIP"
  }
}

# Internal ALB Ingress (internet-facing in dev for convenience)
resource "kubernetes_ingress_v1" "hello" {
  metadata {
    name      = "hello-world"
    namespace = kubernetes_namespace.hiive.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"               = "alb"
      "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"     = "ip"
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.hello.metadata[0].name
              port { number = 80 }
            }
          }
        }
      }
    }
  }
}
