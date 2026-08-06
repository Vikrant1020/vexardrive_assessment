resource "random_password" "admin_password" {
  length           = 32
  special          = true
  override_special = "_%@"
}

resource "azurerm_key_vault_secret" "admin_password" {
  name         = "${var.name}-admin-password"
  value        = random_password.admin_password.result
  key_vault_id = var.key_vault_id
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = var.server_version
  administrator_login           = var.administrator_login
  administrator_password        = random_password.admin_password.result
  sku_name                      = var.sku_name
  storage_mb                    = var.storage_mb
  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = var.private_dns_zone_id
  public_network_access_enabled = var.public_network_access_enabled
  zone                          = var.zone
  backup_retention_days         = var.backup_retention_days
  geo_redundant_backup_enabled  = var.geo_redundant_backup_enabled

  dynamic "high_availability" {
    for_each = var.ha_mode != "Yes" ? [1] : []
    content {
      mode                      = var.ha_mode
      standby_availability_zone = var.ha_standby_zone
    }
  }

  tags = var.tags
}
