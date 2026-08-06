variable "name" {}
variable "resource_group_name" {}
variable "location" {}
variable "server_version" {}
variable "administrator_login" {}
variable "key_vault_id" {
  description = "The ID of the Key Vault where the generated administrator password will be stored"
  type        = string
}
variable "sku_name" {}
variable "storage_mb" {}
variable "delegated_subnet_id" {}
variable "private_dns_zone_id" {}
variable "tags" { type = map(string) }

variable "public_network_access_enabled" {
  type    = bool
  default = false
}

variable "zone" {
  type    = string
  default = "1"
}

variable "backup_retention_days" {
  type    = number
  default = 35
}

variable "geo_redundant_backup_enabled" {
  type    = bool
  default = false
}

variable "ha_mode" {
  description = "High availability mode. Set to empty string to disable HA."
  type        = string
  default     = ""
}

variable "ha_standby_zone" {
  type    = string
  default = "2"
}
