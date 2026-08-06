variable "name" {}
variable "value" { sensitive = true }
variable "key_vault_id" {}
variable "depends_on_role" { default = "" }
