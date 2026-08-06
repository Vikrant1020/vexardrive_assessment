variable "name" {}
variable "resource_group_name" {}
variable "location" {}
variable "tags" { type = map(string) }

variable "sku" {
  type    = string
  default = "Premium"
}

variable "admin_enabled" {
  type    = bool
  default = false
}

variable "public_network_access_enabled" {
  type    = bool
  default = false
}
