resource "azurerm_web_application_firewall_policy" "main" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  policy_settings {
    enabled                     = var.policy_enabled
    mode                        = var.policy_mode
    request_body_check          = var.request_body_check
    max_request_body_size_in_kb = var.max_request_body_size_in_kb
    file_upload_limit_in_mb     = var.file_upload_limit_in_mb
  }

  managed_rules {
    dynamic "managed_rule_set" {
      for_each = var.managed_rule_sets
      content {
        type    = managed_rule_set.value.type
        version = managed_rule_set.value.version
      }
    }
  }
}
