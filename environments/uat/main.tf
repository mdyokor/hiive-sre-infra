# environments/uat/main.tf
# ---------------------------------------------------------------------------
# UAT environment — mirrors prod topology at lower cost.
# Private API endpoint, On-Demand nodes, multi-AZ NAT.
# ---------------------------------------------------------------------------

locals {
  environment  = "uat"
  cluster_name = "hiive-${local.environment}"
  region       = "us-east-1"

  common_tags = {
    Environment = local.environment
    Project     = "hiive"
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  cluster_name       = local.cluster_name
  region             = local.region
  vpc_cidr           = "10.20.0.0/16"
  single_nat_gateway = true   # Single NAT acceptable in UAT; use false to mirror prod
  tags               = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = local.cluster_name
  environment         = local.environment
  kubernetes_version  = "1.29"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids

  # UAT: private API endpoint — engineers need VPN/bastion
  endpoint_public_access = false

  node_instance_type = "t3.large"
  node_capacity_type = "ON_DEMAND"
  node_desired       = 2
  node_min           = 2
  node_max           = 4

  tags = local.common_tags
}

module "alb_controller" {
  source = "../../modules/alb-controller"

  cluster_name      = module.eks.cluster_name
  vpc_id            = module.vpc.vpc_id
  region            = local.region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  replica_count     = 2
  tags              = local.common_tags
}

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
    replicas = 2   # HA in UAT

    selector {
      match_labels = { app = "hello-world" }
    }

    template {
      metadata {
        labels = { app = "hello-world" }
      }

      spec {
        # Spread pods across AZs
        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "topology.kubernetes.io/zone"
          when_unsatisfiable = "DoNotSchedule"
          label_selector {
            match_labels = { app = "hello-world" }
          }
        }

        container {
          name  = "hello"
          image = "public.ecr.aws/docker/library/nginx:stable-alpine"

          port {
            container_port = 80
          }

          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "256Mi" }
          }

          liveness_probe {
            http_get { path = "/"; port = 80 }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get { path = "/"; port = 80 }
            initial_delay_seconds = 5
            period_seconds        = 5
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

# Internal ALB in UAT — only reachable within the VPC / VPN
resource "kubernetes_ingress_v1" "hello" {
  metadata {
    name      = "hello-world"
    namespace = kubernetes_namespace.hiive.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"               = "alb"
      "alb.ingress.kubernetes.io/scheme"          = "internal"
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
