variable "name" {}
variable "location" {}
variable "resource_group_name" {}
variable "tags" { type = map(string) }
variable "allocation_method" {
  type    = string
  default = "Static"
}
variable "sku" {
  type    = string
  default = "Standard"
}
