# modules/alb-controller/main.tf
# ---------------------------------------------------------------------------
# AWS Load Balancer Controller — installed via Helm.
# Uses IRSA so it can manage ALBs without node-level IAM permissions.
# ---------------------------------------------------------------------------

# IRSA role for the ALB controller
module "irsa" {
  source = "../irsa"

  role_name            = "${var.cluster_name}-alb-controller"
  oidc_provider_arn    = var.oidc_provider_arn
  oidc_provider_url    = var.oidc_provider_url
  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"
  inline_policy_json   = file("${path.module}/alb-controller-policy.json")
  tags                 = var.tags
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.irsa.role_arn
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  # Run in at least 2 replicas for HA
  set {
    name  = "replicaCount"
    value = var.replica_count
  }

  depends_on = [module.irsa]
}
