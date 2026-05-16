# Publishing to GitHub — Step-by-Step Guide

This guide walks you through creating the public GitHub repository and wiring up
the CI/CD pipeline so that Terraform plans run on every PR and applies are gated
by environment approval.

---

## Step 1 — Create the GitHub Repository

### Option A: GitHub CLI (fastest)

```bash
# Install gh if not already: brew install gh
gh auth login
gh repo create hiive-sre-infra --public --description "Hiive platform Terraform IaC"
```

### Option B: GitHub Web UI

1. Go to https://github.com/new
2. Repository name: `hiive-sre-infra`
3. Visibility: **Public**
4. Do **not** initialise with README (we already have one)
5. Click **Create repository**

---

## Step 2 — Push the Code

```bash
cd hiive-sre-infra

git init
git add .
git commit -m "feat: initial EKS Terraform for dev/uat/prod"

git remote add origin https://github.com/<your-handle>/hiive-sre-infra.git
git branch -M main
git push -u origin main
```

---

## Step 3 — Create AWS IAM Roles for GitHub Actions (OIDC)

GitHub Actions authenticates to AWS via OIDC — no long-lived credentials stored
as secrets.

```bash
# Run once per environment (dev / uat / prod)
ENV=dev   # change to uat or prod

aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Create a plan role (read-only) and an apply role per environment
# See the full trust policy template below.
```

**Trust policy template** — save as `trust-policy.json`, replace placeholders:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub":
            "repo:<YOUR_GITHUB_HANDLE>/hiive-sre-infra:environment:<ENV>"
        }
      }
    }
  ]
}
```

```bash
aws iam create-role \
  --role-name hiive-tf-apply-dev \
  --assume-role-policy-document file://trust-policy.json

# Attach AdministratorAccess for initial setup; scope down later
aws iam attach-role-policy \
  --role-name hiive-tf-apply-dev \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

Repeat for `hiive-tf-plan-dev`, `hiive-tf-apply-uat`, `hiive-tf-plan-uat`,
`hiive-tf-apply-prod`, `hiive-tf-plan-prod`.

---

## Step 4 — Configure GitHub Repository Secrets

Go to **Settings → Secrets and variables → Actions → New repository secret**:

| Secret name              | Value                                  |
|--------------------------|----------------------------------------|
| `AWS_PLAN_ROLE_DEV`      | ARN of `hiive-tf-plan-dev`             |
| `AWS_PLAN_ROLE_UAT`      | ARN of `hiive-tf-plan-uat`             |
| `AWS_PLAN_ROLE_PROD`     | ARN of `hiive-tf-plan-prod`            |
| `AWS_APPLY_ROLE_DEV`     | ARN of `hiive-tf-apply-dev`            |
| `AWS_APPLY_ROLE_UAT`     | ARN of `hiive-tf-apply-uat`            |
| `AWS_APPLY_ROLE_PROD`    | ARN of `hiive-tf-apply-prod`           |
| `ACM_CERT_ARN`           | ARN of the prod ACM certificate        |
| `APP_HOSTNAME`           | e.g. `app.hiive.com`                   |

---

## Step 5 — Configure GitHub Environments (Approval Gates)

Go to **Settings → Environments** and create three environments:

### `dev`
- No protection rules (auto-applies on merge to main)

### `uat`
- ✅ Required reviewers: add at least one SRE
- Deployment branches: `main` only

### `prod`
- ✅ Required reviewers: add the on-call SRE + engineering lead
- ✅ Wait timer: 5 minutes (gives time to abort if dev apply fails)
- Deployment branches: `main` only

Also create `dev-plan`, `uat-plan`, `prod-plan` environments with **read-only**
roles (no approval gates needed for plans).

---

## Step 6 — Protect the Main Branch

Go to **Settings → Branches → Add branch ruleset**:

- Branch name pattern: `main`
- ✅ Require pull request before merging
- ✅ Require status checks: `lint`, `Plan (dev)`, `Plan (uat)`, `Plan (prod)`
- ✅ Require linear history
- ✅ Do not allow force pushes

---

## Step 7 — Create the S3 Backend (if not done yet)

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

aws dynamodb create-table \
  --table-name hiive-tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Update `backend.tf` in each environment folder — replace `<account-id>` with
`${ACCOUNT_ID}`.

---

## Step 8 — First Deploy

```bash
# Bootstrap dev manually (CI needs the cluster to exist before it can configure kubectl)
cd environments/dev
terraform init
terraform apply -auto-approve

# Then open a PR with any change to trigger the full CI pipeline
git checkout -b test/pipeline-smoke-test
echo "# smoke test" >> README.md
git add README.md
git commit -m "ci: smoke-test pipeline"
git push origin test/pipeline-smoke-test
gh pr create --title "ci: smoke-test pipeline" --body "Testing the Terraform CI pipeline."
```

Watch the **Actions** tab — you should see plan output posted as a PR comment for
all three environments.

---

## Promotion Flow (after first deploy)

```
Developer opens PR
  └─ CI: fmt check + validate + plan (dev/uat/prod) → comments on PR
Reviewer approves PR
  └─ Merge to main
      ├─ Auto-apply dev  (no approval)
      ├─ SRE approves  → apply uat
      └─ Lead approves → apply prod
```
