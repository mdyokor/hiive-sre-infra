# environments/dev/backend.tf
# State stored in S3 with DynamoDB locking.
# Replace <account-id> before running terraform init.

terraform {
  backend "s3" {
    bucket         = "hiive-tfstate-<account-id>"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "hiive-tf-locks"
  }
}
