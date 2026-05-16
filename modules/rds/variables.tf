variable "identifier"             { type = string }
variable "vpc_id"                 { type = string }
variable "private_subnet_ids"     { type = list(string) }
variable "node_security_group_id" { type = string }
variable "engine_version"         { type = string;       default = "15.5" }
variable "instance_class"         { type = string;       default = "db.t3.medium" }
variable "allocated_storage"      { type = number;       default = 20 }
variable "max_allocated_storage"  { type = number;       default = 100 }
variable "db_name"                { type = string;       default = "hiive" }
variable "db_username"            { type = string;       default = "hiive_admin" }
variable "db_password"            { type = string;       sensitive = true }
variable "multi_az"               { type = bool;         default = false }
variable "backup_retention_days"  { type = number;       default = 7 }
variable "delete_automated_backups" { type = bool;       default = true }
variable "deletion_protection"    { type = bool;         default = false }
variable "tags"                   { type = map(string);  default = {} }
