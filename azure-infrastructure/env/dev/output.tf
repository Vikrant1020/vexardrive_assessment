output "resource_group_name" { value = azurerm_resource_group.main.name }
output "appgw_public_ip" { value = module.pip.ip_address }
output "container_app_fqdn" { value = module.ca.fqdn }
output "acr_login_server" { value = module.acr.login_server }
output "postgres_fqdn" { value = module.postgres.fqdn }
output "keyvault_uri" { value = module.kv.vault_uri }
