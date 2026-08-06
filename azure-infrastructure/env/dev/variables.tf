variable "project_name" { default = "vexar-fleet" }
variable "environment" { default = "dev" }
variable "location" { default = "eastus" }
variable "vnet_address_space" { default = ["10.0.0.0/16"] }
variable "subnet_appgw" { default = "10.0.1.0/24" }
variable "subnet_container_apps" { default = "10.0.2.0/23" }
variable "subnet_db" { default = "10.0.4.0/24" }
variable "subnet_private_endpoints" { default = "10.0.5.0/24" }
variable "db_admin_username" { default = "vexaradmin" }

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  tags = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
  }
}