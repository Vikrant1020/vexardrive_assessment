resource "azurerm_subnet" "main" {
  name                 = var.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.virtual_network_name
  address_prefixes     = var.address_prefixes

  dynamic "delegation" {
    for_each = var.delegation_name != "" ? [1] : []
    content {
      name = var.delegation_name
      service_delegation {
        name    = var.service_delegation_name
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }
}
