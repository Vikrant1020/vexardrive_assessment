output "id" { value = azurerm_container_app.main.id }
output "fqdn" { value = azurerm_container_app.main.ingress[0].fqdn }
