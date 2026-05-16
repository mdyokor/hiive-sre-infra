variable "cluster_name"       { type = string }
variable "vpc_id"             { type = string }
variable "region"             { type = string }
variable "oidc_provider_arn"  { type = string }
variable "oidc_provider_url"  { type = string }
variable "chart_version"      { type = string; default = "1.7.1" }
variable "replica_count"      { type = number; default = 2 }
variable "tags"               { type = map(string); default = {} }
