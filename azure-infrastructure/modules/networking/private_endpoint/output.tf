output "id" { value = azurerm_private_endpoint.main.id }
output "private_ip_address" {
  value = azurerm_private_endpoint.main.private_service_connection[0].private_ip_address
}
