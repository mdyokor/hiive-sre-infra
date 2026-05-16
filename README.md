# hiive-sre-infra

Terraform infrastructure for the Hiive platform — EKS clusters and PostgreSQL RDS
across **dev**, **uat**, and **prod** environments.

## Repository Layout

```
hiive-sre-infra/
├── modules/
│   ├── vpc/            # VPC, subnets, NAT gateway, VPC endpoints
│   ├── eks/            # EKS cluster + managed node groups
│   ├── rds/            # PostgreSQL RDS + parameter group + Secrets Manager
│   ├── irsa/           # IAM Roles for Service Accounts
│   └── alb-controller/ # AWS Load Balancer Controller (Helm)
├── environments/
│   ├── dev/
│   ├── uat/
│   └── prod/
└── .github/
    └── workflows/      # CI/CD — plan on PR, apply on merge
```

## Related Repositories

- [hiive-datadog-monitors](https://github.com/mdyokor/hiive-datadog-monitors) — Datadog monitors as Terraform IaC

## Prerequisites

| Tool | Version |
|------|---------|
| Terraform | >= 1.7 |
| AWS CLI | >= 2.15 |
| kubectl | >= 1.29 |
| helm | >= 3.14 |

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/mdyokor/hiive-sre-infra.git
cd hiive-sre-infra
```

### 2. Configure AWS credentials

```bash
export AWS_PROFILE=hiive-dev   # or hiive-uat / hiive-prod
export AWS_REGION=us-east-1
```

### 3. Create the S3 backend bucket (one-time per account)

Terraform state is stored in S3. No DynamoDB is used — concurrent apply
protection is enforced via GitHub Actions Environment approval gates.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws s3api create-bucket \
  --bucket hiive-tfstate-${ACCOUNT_ID} \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket hiive-tfstate-${ACCOUNT_ID} \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket hiive-tfstate-${ACCOUNT_ID} \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'

aws s3api put-public-access-block \
  --bucket hiive-tfstate-${ACCOUNT_ID} \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

Then replace <account-id> in each environments/*/backend.tf with your account ID.

### 4. Deploy an environment

```bash
cd environments/dev
export TF_VAR_db_password="a-strong-random-password"
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Repeat for uat and prod with the appropriate AWS profile and credentials.

### 5. Configure kubectl

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name hiive-dev \
  --profile hiive-dev
kubectl get nodes
```

## Environment Differences

| Setting | dev | uat | prod |
|---------|-----|-----|------|
| Node instance type | t3.medium (Spot) | t3.large | m6i.xlarge |
| Min / Max nodes | 1 / 3 | 2 / 4 | 3 / 10 |
| EKS private endpoint only | false | true | true |
| RDS instance type | db.t3.medium | db.t3.large | db.r6g.xlarge |
| RDS Multi-AZ | false | false | true |
| RDS backup retention | 1 day | 3 days | 7 days |
| Deletion protection | false | false | true |
| Cluster Autoscaler | false | false | true |

## Architecture Overview

```
                        Internet
                           |
                    [ALB - public subnets]
                           |
              [EKS Nodes - private subnets]
                           |
              [RDS PostgreSQL - private subnets]
```

- The ALB sits in public subnets and is the only internet-facing component.
- EKS nodes and RDS are in private subnets — never directly reachable from the internet.
- EKS nodes connect to RDS on port 5432 via a scoped security group rule.
- Outbound traffic from nodes goes via NAT gateway (one per AZ in prod for HA).
- VPC endpoints for ECR, S3, and CloudWatch keep image pull and log traffic off the NAT.

## Security Notes

- EKS nodes live in private subnets — no direct internet ingress.
- RDS is in private subnets — only reachable from EKS nodes via security group rules.
- DB credentials are stored in AWS Secrets Manager, not in Terraform state.
- pg_stat_statements is enabled on RDS for query performance monitoring via Datadog.
- The Kubernetes API endpoint is private-only in uat and prod.
- Pods use IRSA (IAM Roles for Service Accounts) — no node-level IAM permissions.
- IMDSv2 is enforced on all EC2 nodes to prevent SSRF-based metadata theft.
- Terraform state is stored encrypted in S3 (KMS). No public access is allowed.

## CI/CD Pipeline

```
Developer opens PR
  └─ CI: fmt check + validate + plan (dev / uat / prod) → comments on PR
Reviewer approves and merges to main
  ├─ Auto-apply dev      (no approval gate)
  ├─ SRE approves    →   apply uat
  └─ Lead approves   →   apply prod
```

GitHub Actions uses OIDC to authenticate to AWS — no long-lived credentials
are stored as repository secrets.

## Passing the Database Password

Never hardcode the database password. Always pass it as an environment variable:

```bash
export TF_VAR_db_password="a-strong-random-password"
terraform apply
```

In CI/CD, store it as a GitHub Actions secret (DB_PASSWORD_DEV, DB_PASSWORD_UAT,
DB_PASSWORD_PROD) and reference it in the workflow.
