# hiive-sre-infra

Terraform infrastructure for the Hiive platform — EKS clusters across **dev**, **uat**, and **prod** environments.

## Repository Layout

```
hiive-sre-infra/
├── modules/
│   ├── vpc/            # VPC, subnets, NAT gateway, VPC endpoints
│   ├── eks/            # EKS cluster + managed node groups
│   ├── irsa/           # IAM Roles for Service Accounts
│   └── alb-controller/ # AWS Load Balancer Controller (Helm)
├── environments/
│   ├── dev/
│   ├── uat/
│   └── prod/
├── datadog/
│   └── monitors/       # Datadog monitor definitions (IaC)
└── .github/
    └── workflows/      # CI/CD — plan on PR, apply on merge
```

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
git clone https://github.com/<your-handle>/hiive-sre-infra.git
cd hiive-sre-infra
```

### 2. Configure AWS credentials

```bash
export AWS_PROFILE=hiive-dev   # or hiive-uat / hiive-prod
export AWS_REGION=us-east-1
```

### 3. Create S3 backend bucket and DynamoDB lock table (one-time per account)

```bash
# Replace <account-id> with your AWS account ID
aws s3api create-bucket \
  --bucket hiive-tfstate-<account-id> \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket hiive-tfstate-<account-id> \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name hiive-tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 4. Deploy an environment

```bash
cd environments/dev
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

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
| Node instance type | t3.medium | t3.large | m6i.xlarge |
| Min / Max nodes | 1 / 3 | 2 / 4 | 3 / 10 |
| EKS private endpoint only | false | true | true |
| Deletion protection | false | false | true |

## Promotion Workflow

```
feature branch → PR → plan (CI) → merge to main → apply dev (CI)
                                                  → manual approval → apply uat
                                                  → manual approval → apply prod
```
