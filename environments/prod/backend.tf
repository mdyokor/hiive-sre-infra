terraform {
  backend "s3" {
    bucket         = "hiive-tfstate-<account-id>"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "hiive-tf-locks"
  }
}
