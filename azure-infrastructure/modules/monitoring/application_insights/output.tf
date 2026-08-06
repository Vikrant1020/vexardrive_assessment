output "id" { value = azurerm_application_insights.main.id }
output "connection_string" {
  value     = azurerm_application_insights.main.connection_string
  sensitive = true
}
