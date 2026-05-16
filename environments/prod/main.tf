# environments/prod/main.tf
# ---------------------------------------------------------------------------
# Production environment — full HA, private API endpoint, On-Demand nodes,
# one NAT gateway per AZ, deletion protection, stricter resource limits.
# ---------------------------------------------------------------------------

locals {
  environment  = "prod"
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
  vpc_cidr           = "10.30.0.0/16"
  single_nat_gateway = false   # One NAT per AZ for HA — node traffic survives an AZ failure
  tags               = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = local.cluster_name
  environment         = local.environment
  kubernetes_version  = "1.29"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids

  # Prod: private endpoint ONLY. CI/CD must run inside VPC or via VPN.
  endpoint_public_access = false

  node_instance_type = "m6i.xlarge"
  node_capacity_type = "ON_DEMAND"
  node_desired       = 3
  node_min           = 3
  node_max           = 10

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

# ---------------------------------------------------------------------------
# Cluster Autoscaler (IRSA + Helm) — required for node_max > node_desired
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${local.cluster_name}"
      values   = ["owned"]
    }
  }
}

module "cluster_autoscaler_irsa" {
  source = "../../modules/irsa"

  role_name            = "${local.cluster_name}-cluster-autoscaler"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "kube-system"
  service_account_name = "cluster-autoscaler"
  inline_policy_json   = data.aws_iam_policy_document.cluster_autoscaler.json
  tags                 = local.common_tags
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.36.0"
  namespace  = "kube-system"

  set { name = "autoDiscovery.clusterName"; value = module.eks.cluster_name }
  set { name = "awsRegion";                 value = local.region }
  set { name = "serviceAccount.create";     value = "true" }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.cluster_autoscaler_irsa.role_arn
  }
  set { name = "extraArgs.balance-similar-node-groups"; value = "true" }
  set { name = "extraArgs.skip-nodes-with-system-pods"; value = "false" }

  depends_on = [module.eks]
}

# ---------------------------------------------------------------------------
# Application namespace and workload
# ---------------------------------------------------------------------------
resource "kubernetes_namespace" "hiive" {
  metadata {
    name   = "hiive"
    labels = { environment = local.environment }
  }
}

# PodDisruptionBudget — keep at least 2 pods up during node drains
resource "kubernetes_pod_disruption_budget_v1" "hello" {
  metadata {
    name      = "hello-world-pdb"
    namespace = kubernetes_namespace.hiive.metadata[0].name
  }

  spec {
    min_available = "50%"
    selector {
      match_labels = { app = "hello-world" }
    }
  }
}

resource "kubernetes_deployment_v1" "hello" {
  metadata {
    name      = "hello-world"
    namespace = kubernetes_namespace.hiive.metadata[0].name
    labels    = { app = "hello-world" }
  }

  spec {
    replicas = 3

    selector {
      match_labels = { app = "hello-world" }
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = "25%"
        max_surge       = "25%"
      }
    }

    template {
      metadata {
        labels = { app = "hello-world" }
        annotations = {
          # Force pods to re-pull on deployment even with :latest tags
          "kubectl.kubernetes.io/restartedAt" = timestamp()
        }
      }

      spec {
        # Hard anti-affinity — never two pods on the same node
        affinity {
          pod_anti_affinity {
            required_during_scheduling_ignored_during_execution {
              label_selector {
                match_expressions {
                  key      = "app"
                  operator = "In"
                  values   = ["hello-world"]
                }
              }
              topology_key = "kubernetes.io/hostname"
            }
          }
        }

        # Spread across AZs
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

          port { container_port = 80 }

          resources {
            requests = { cpu = "200m", memory = "256Mi" }
            limits   = { cpu = "1000m", memory = "512Mi" }
          }

          liveness_probe {
            http_get { path = "/"; port = 80 }
            initial_delay_seconds = 5
            period_seconds        = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get { path = "/"; port = 80 }
            initial_delay_seconds = 5
            period_seconds        = 5
            failure_threshold     = 3
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

# Internet-facing ALB in public subnets; nodes stay in private subnets
resource "kubernetes_ingress_v1" "hello" {
  metadata {
    name      = "hello-world"
    namespace = kubernetes_namespace.hiive.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                        = "alb"
      "alb.ingress.kubernetes.io/scheme"                   = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"              = "ip"
      "alb.ingress.kubernetes.io/subnets"                  = join(",", module.vpc.public_subnet_ids)
      "alb.ingress.kubernetes.io/listen-ports"             = "[{\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"             = "443"
      "alb.ingress.kubernetes.io/certificate-arn"          = var.acm_certificate_arn
      "alb.ingress.kubernetes.io/healthcheck-path"         = "/health"
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=60"
    }
  }

  spec {
    rule {
      host = var.app_hostname
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
