variable "name" {}
variable "server_id" {}

variable "charset" {
  type    = string
  default = "UTF8"
}

variable "collation" {
  type    = string
  default = "en_US.utf8"
}
