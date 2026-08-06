variable "name" {}
variable "resource_group_name" {}
variable "virtual_network_name" {}
variable "address_prefixes" { type = list(string) }
variable "delegation_name" { default = "" }
variable "service_delegation_name" { default = "" }
