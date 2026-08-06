output "id" { value = azurerm_postgresql_flexible_server.main.id }
output "fqdn" { value = azurerm_postgresql_flexible_server.main.fqdn }
output "admin_password_secret_id" { value = azurerm_key_vault_secret.admin_password.id }
