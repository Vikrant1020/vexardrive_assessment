variable "name" {}
variable "resource_group_name" {}
variable "short_name" {}
variable "tags" { type = map(string) }

variable "email_receivers" {
  description = "List of email receivers for the action group"
  type = list(object({
    name          = string
    email_address = string
  }))
  default = []
}
