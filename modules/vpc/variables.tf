# modules/vpc/variables.tf

variable "cluster_name" {
  description = "Name of the EKS cluster — used for resource naming and subnet tags."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway (cheaper for dev/uat). Set false in prod for HA."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
