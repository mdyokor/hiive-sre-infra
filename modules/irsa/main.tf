# modules/irsa/main.tf
# Creates a scoped IAM role that a Kubernetes ServiceAccount can assume
# via the EKS OIDC provider (IRSA - IAM Roles for Service Accounts).

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each   = toset(var.policy_arns)
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_policy" "inline" {
  count       = var.inline_policy_json != "" ? 1 : 0
  name        = "${var.role_name}-inline"
  description = "Inline policy for ${var.role_name}"
  policy      = var.inline_policy_json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "inline" {
  count      = var.inline_policy_json != "" ? 1 : 0
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.inline[0].arn
}
