resource "azurerm_container_app" "main" {
  name                         = var.name
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = var.revision_mode
  workload_profile_name        = var.workload_profile_name
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = var.identity_ids
  }

  registry {
    server   = var.acr_login_server
    identity = var.identity_ids[0]
  }

  dynamic "secret" {
    for_each = { for idx, s in var.container_secrets : idx => s }
    iterator = secret_item

    content {
      name                = secret_item.value.name
      value               = lookup(secret_item.value, "value", null)
      key_vault_secret_id = lookup(secret_item.value, "key_vault_secret_id", null)
      identity            = lookup(secret_item.value, "identity", null)
    }
  }

  ingress {
    external_enabled = false
    target_port      = var.target_port
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = var.container_min_replicas
    max_replicas = var.container_max_replicas

    custom_scale_rule {
      name             = "cputhreshold"
      custom_rule_type = "cpu"
      metadata = {
        type  = "Utilization"
        value = "70"
      }
    }

    container {
      name   = "fleet-ping"
      image  = var.container_image != "" ? var.container_image : "nginx:latest"
      cpu    = var.container_cpu
      memory = var.container_memory

      dynamic "env" {
        for_each = var.environment_variables
        iterator = env_item

        content {
          name        = env_item.value.name
          value       = try(env_item.value.value, null)
          secret_name = try(env_item.value.secret_name, null)
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image, ingress[0].target_port]
  }
}
