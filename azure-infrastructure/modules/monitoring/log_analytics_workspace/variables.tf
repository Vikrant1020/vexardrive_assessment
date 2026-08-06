variable "name" {}
variable "location" {}
variable "resource_group_name" {}
variable "tags" { type = map(string) }

variable "sku" {
  type    = string
  default = "PerGB2018"
}

variable "retention_in_days" {
  type    = number
  default = 30
}
