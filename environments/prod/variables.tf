# environments/prod/variables.tf
# These are supplied via a *.tfvars file or CI environment variables.
# Never commit actual values for acm_certificate_arn or app_hostname.

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS on the production ALB."
  type        = string
}

variable "app_hostname" {
  description = "FQDN for the production application (e.g. app.hiive.com)."
  type        = string
}
