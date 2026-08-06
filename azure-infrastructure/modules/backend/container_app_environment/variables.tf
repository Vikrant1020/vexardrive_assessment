variable "name" {}
variable "location" {}
variable "resource_group_name" {}
variable "log_analytics_workspace_id" {}
variable "infrastructure_subnet_id" {}
variable "tags" { type = map(string) }

variable "internal_load_balancer_enabled" {
  type    = bool
  default = true
}
