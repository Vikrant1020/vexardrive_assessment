variable "name" {}
variable "location" {}
variable "resource_group_name" {}
variable "subnet_id" {}
variable "private_connection_resource_id" {}
variable "tags" { type = map(string) }

variable "subresource_names" {
  description = "List of subresource names for the private service connection"
  type        = list(string)
}

variable "service_connection_name" {
  type    = string
  default = "psc"
}

variable "is_manual_connection" {
  type    = bool
  default = false
}

variable "enable_dns_zone_group" {
  type    = bool
  default = true
}

variable "dns_zone_group_name" {
  type    = string
  default = "pdns-group"
}

variable "private_dns_zone_ids" {
  type    = list(string)
  default = []
}
