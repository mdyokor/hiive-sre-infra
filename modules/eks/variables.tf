# modules/eks/variables.tf

variable "cluster_name"         { type = string }
variable "environment"          { type = string }
variable "kubernetes_version"   { type = string; default = "1.29" }
variable "vpc_id"               { type = string }
variable "private_subnet_ids"   { type = list(string) }
variable "alb_security_group_ids" { type = list(string); default = [] }
variable "app_port"             { type = number; default = 4000 }
variable "node_instance_type"   { type = string; default = "t3.medium" }
variable "node_capacity_type"   { type = string; default = "ON_DEMAND" }
variable "node_desired"         { type = number; default = 2 }
variable "node_min"             { type = number; default = 1 }
variable "node_max"             { type = number; default = 3 }
variable "endpoint_public_access" { type = bool; default = false }
variable "api_allowed_cidrs"    { type = list(string); default = ["0.0.0.0/0"] }
variable "tags"                 { type = map(string); default = {} }
