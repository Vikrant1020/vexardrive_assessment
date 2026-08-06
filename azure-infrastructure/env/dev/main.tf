resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

# ============================================================================
# NETWORKING
# ============================================================================
module "vnet" {
  source              = "../../modules/networking/virtual_network"
  name                = "vnet-${local.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = local.tags
}

module "subnet_appgw" {
  source               = "../../modules/networking/subnet"
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = module.vnet.name
  address_prefixes     = [var.subnet_appgw]
}

module "subnet_container_apps" {
  source                  = "../../modules/networking/subnet"
  name                    = "snet-container-apps"
  resource_group_name     = azurerm_resource_group.main.name
  virtual_network_name    = module.vnet.name
  address_prefixes        = [var.subnet_container_apps]
  delegation_name         = "container-apps-delegation"
  service_delegation_name = "Microsoft.App/environments"
}

module "subnet_db" {
  source                  = "../../modules/networking/subnet"
  name                    = "snet-db"
  resource_group_name     = azurerm_resource_group.main.name
  virtual_network_name    = module.vnet.name
  address_prefixes        = [var.subnet_db]
  delegation_name         = "postgres-delegation"
  service_delegation_name = "Microsoft.DBforPostgreSQL/flexibleServers"
}

module "subnet_pe" {
  source               = "../../modules/networking/subnet"
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = module.vnet.name
  address_prefixes     = [var.subnet_private_endpoints]
}

module "nsg" {
  source              = "../../modules/networking/network_security_group"
  name                = "nsg-appgw-${local.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags

  security_rules = [
    {
      name                       = "AllowHTTPS"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowHTTP"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowGatewayManager"
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "65200-65535"
      source_address_prefix      = "GatewayManager"
      destination_address_prefix = "*"
    },
  ]
}

module "nsg_assoc" {
  source                    = "../../modules/networking/subnet_nsg_association"
  subnet_id                 = module.subnet_appgw.id
  network_security_group_id = module.nsg.id
}

# --- Private DNS Zones ---
module "pdns_pg" {
  source              = "../../modules/networking/private_dns_zone"
  name                = "${local.name_prefix}.private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

module "pdns_link_pg" {
  source              = "../../modules/networking/private_dns_zone_vnet_link"
  name                = "pdnslink-postgres"
  private_dns_zone_id = module.pdns_pg.id
  virtual_network_id  = module.vnet.id
}

module "pdns_kv" {
  source              = "../../modules/networking/private_dns_zone"
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

module "pdns_link_kv" {
  source              = "../../modules/networking/private_dns_zone_vnet_link"
  name                = "pdnslink-keyvault"
  private_dns_zone_id = module.pdns_kv.id
  virtual_network_id  = module.vnet.id
}

module "pdns_acr" {
  source              = "../../modules/networking/private_dns_zone"
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

module "pdns_link_acr" {
  source              = "../../modules/networking/private_dns_zone_vnet_link"
  name                = "pdnslink-acr"
  private_dns_zone_id = module.pdns_acr.id
  virtual_network_id  = module.vnet.id
}

# ============================================================================
# BACKEND
# ============================================================================

# --- ACR ---
module "acr" {
  source              = "../../modules/backend/container_registry"
  name                = replace("acr${local.name_prefix}", "-", "")
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.tags
}

module "pe_acr" {
  source                         = "../../modules/networking/private_endpoint"
  name                           = "pe-acr-${local.name_prefix}"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.main.name
  subnet_id                      = module.subnet_pe.id
  private_connection_resource_id = module.acr.id
  subresource_names              = ["registry"]
  private_dns_zone_ids           = [module.pdns_acr.id]
  tags                           = local.tags
}

# --- Container App ---
module "cae" {
  source                     = "../../modules/backend/container_app_environment"
  name                       = "cae-${local.name_prefix}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = module.law.id
  infrastructure_subnet_id   = module.subnet_container_apps.id
  tags                       = local.tags
}

resource "azurerm_user_assigned_identity" "ca" {
  name                = "id-ca-${local.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

module "ca" {
  source                       = "../../modules/backend/container_app"
  name                         = "ca-${local.name_prefix}"
  container_app_environment_id = module.cae.id
  resource_group_name          = azurerm_resource_group.main.name
  acr_login_server             = module.acr.login_server
  container_cpu                = 0.25
  container_memory             = "0.5Gi"
  container_min_replicas       = 1
  container_max_replicas       = 2
  environment                  = var.environment
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  identity_ids                 = [azurerm_user_assigned_identity.ca.id]
  tags                         = local.tags
  target_port                  = 80

  container_secrets = [
    {
      name                = "db-password"
      key_vault_secret_id = module.postgres.admin_password_secret_id
      identity            = azurerm_user_assigned_identity.ca.id
    },
    {
      name                = "jwt-secret"
      key_vault_secret_id = module.secret_jwt.id
      identity            = azurerm_user_assigned_identity.ca.id
    },
  ]

  environment_variables = [
    { name = "PORT", value = "3000" },
    { name = "NODE_ENV", value = "production" },
    { name = "DB_HOST", value = module.postgres.fqdn },
    { name = "DB_PORT", value = "5432" },
    { name = "DB_USER", value = var.db_admin_username },
    { name = "DB_NAME", value = "vexar_fleet" },
    { name = "DB_SSL", value = "true" },
    { name = "LOG_LEVEL", value = var.environment == "prod" ? "info" : "debug" },
    { name = "APPLICATIONINSIGHTS_CONNECTION_STRING", value = module.appi.connection_string },
    { name = "DB_PASSWORD", secret_name = "db-password" },
    { name = "JWT_SECRET", secret_name = "jwt-secret" },
  ]
}

# --- App Gateway ---
module "pip" {
  source              = "../../modules/networking/public_ip"
  name                = "pip-appgw-${local.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

module "waf" {
  source              = "../../modules/backend/web_application_firewall_policy"
  name                = "waf-${local.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

module "appgw" {
  source              = "../../modules/backend/application_gateway"
  name                = "appgw-${local.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  firewall_policy_id  = module.waf.id
  subnet_id           = module.subnet_appgw.id
  autoscale_min       = var.environment == "prod" ? 2 : 1
  autoscale_max       = var.environment == "prod" ? 10 : 3
  tags                = local.tags

  frontend_ip_configurations = [
    { name = "fe-ip", public_ip_address_id = module.pip.id },
  ]

  frontend_ports = [
    { name = "fe-port-http", port = 80 },
    { name = "fe-port-https", port = 443 },
  ]

  backend_address_pools = [
    { name = "bp-container-app", fqdns = [module.cae.default_domain] },
  ]

  backend_http_settings = [
    {
      name                                = "bhs-container-app"
      cookie_based_affinity               = "Disabled"
      port                                = 443
      protocol                            = "Https"
      request_timeout                     = 30
      pick_host_name_from_backend_address = true
      probe_name                          = "probe-health"
    },
  ]

  health_probes = [
    {
      name                                      = "probe-health"
      protocol                                  = "Https"
      path                                      = "/health"
      interval                                  = 30
      timeout                                   = 10
      unhealthy_threshold                       = 3
      pick_host_name_from_backend_http_settings = true
    },
  ]

  http_listeners = [
    { name = "listener-http", frontend_ip_configuration_name = "fe-ip", frontend_port_name = "fe-port-http", protocol = "Http" },
    { name = "listener-https", frontend_ip_configuration_name = "fe-ip", frontend_port_name = "fe-port-https", protocol = "Http" },
  ]

  redirect_configurations = [
    {
      name                 = "redirect-http-to-https"
      redirect_type        = "Permanent"
      target_listener_name = "listener-https"
      include_path         = true
      include_query_string = true
    },
  ]

  request_routing_rules = [
    {
      name                        = "rule-http-redirect"
      priority                    = 100
      rule_type                   = "Basic"
      http_listener_name          = "listener-http"
      redirect_configuration_name = "redirect-http-to-https"
    },
    {
      name                       = "rule-https"
      priority                   = 200
      rule_type                  = "Basic"
      http_listener_name         = "listener-https"
      backend_address_pool_name  = "bp-container-app"
      backend_http_settings_name = "bhs-container-app"
    },
  ]
}

# ============================================================================
# DATABASE
# ============================================================================
module "postgres" {
  source              = "../../modules/database/postgresql_flexible_server"
  name                = "psql-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  server_version      = 16
  administrator_login = var.db_admin_username
  key_vault_id        = module.kv.id
  sku_name            = "B_Standard_B1ms"
  storage_mb          = 32768
  delegated_subnet_id = module.subnet_db.id
  private_dns_zone_id = module.pdns_pg.id
  tags                = local.tags
}

module "pg_conf_pool" {
  source    = "../../modules/database/postgresql_flexible_server_config"
  name      = "pgbouncer.enabled"
  server_id = module.postgres.id
  value     = "true"
}

module "pg_db" {
  source    = "../../modules/database/postgresql_flexible_server_database"
  name      = "vexar_fleet"
  server_id = module.postgres.id
}

# ============================================================================
# SECURITY
# ============================================================================
module "kv" {
  source              = "../../modules/security/key_vault"
  name                = "kv-${local.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.tags
}

module "pe_kv" {
  source                         = "../../modules/networking/private_endpoint"
  name                           = "pe-kv-${local.name_prefix}"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.main.name
  subnet_id                      = module.subnet_pe.id
  private_connection_resource_id = module.kv.id
  subresource_names              = ["vault"]
  private_dns_zone_ids           = [module.pdns_kv.id]
  tags                           = local.tags
}

module "role_kv_admin" {
  source               = "../../modules/security/role_assignment"
  scope                = module.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

module "role_ca_kv" {
  source               = "../../modules/security/role_assignment"
  scope                = module.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.ca.principal_id
}

module "role_ca_acr" {
  source               = "../../modules/security/role_assignment"
  scope                = module.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.ca.principal_id
}


# Generated by Terraform, same pattern as the DB admin password — never entered
# manually as a -var, which would otherwise risk shell-history/CI-log exposure.
resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

module "secret_jwt" {
  source       = "../../modules/security/key_vault_secret"
  name         = "jwt-secret"
  value        = random_password.jwt_secret.result
  key_vault_id = module.kv.id
}

# ============================================================================
# MONITORING
# ============================================================================
module "law" {
  source              = "../../modules/monitoring/log_analytics_workspace"
  name                = "law-${local.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  retention_in_days   = var.environment == "prod" ? 90 : 30
  tags                = local.tags
}

module "appi" {
  source              = "../../modules/monitoring/application_insights"
  name                = "appi-${local.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = module.law.id
  application_type    = "Node.JS"
  tags                = local.tags
}

module "action_group" {
  source              = "../../modules/monitoring/monitor_action_group"
  name                = "ag-ops-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "ops-alert"
  tags                = local.tags

  email_receivers = [
    { name = "ops-email", email_address = "ops@vexardrive.com" },
  ]
}

# --- Metric Alerts ---
module "alert_ca_5xx" {
  source              = "../../modules/monitoring/monitor_metric_alert"
  name                = "alert-ca-5xx-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [module.ca.id]
  description         = "Container App HTTP 5xx rate exceeded threshold"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"
  metric_namespace    = "Microsoft.App/containerApps"
  metric_name         = "Http5xx"
  aggregation         = "Total"
  operator            = "GreaterThan"
  threshold           = 10
  action_group_id     = module.action_group.id
  tags                = local.tags
}

module "alert_pg_cpu" {
  source              = "../../modules/monitoring/monitor_metric_alert"
  name                = "alert-pg-cpu-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [module.postgres.id]
  description         = "PostgreSQL CPU usage above 80%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  metric_namespace    = "Microsoft.DBforPostgreSQL/flexibleServers"
  metric_name         = "cpu_percent"
  aggregation         = "Average"
  operator            = "GreaterThan"
  threshold           = 80
  action_group_id     = module.action_group.id
  tags                = local.tags
}

module "alert_pg_storage" {
  source              = "../../modules/monitoring/monitor_metric_alert"
  name                = "alert-pg-storage-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [module.postgres.id]
  description         = "PostgreSQL storage usage above 85%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  metric_namespace    = "Microsoft.DBforPostgreSQL/flexibleServers"
  metric_name         = "storage_percent"
  aggregation         = "Average"
  operator            = "GreaterThan"
  threshold           = 85
  action_group_id     = module.action_group.id
  tags                = local.tags
}

module "alert_pg_connections" {
  source              = "../../modules/monitoring/monitor_metric_alert"
  name                = "alert-pg-connections-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [module.postgres.id]
  description         = "PostgreSQL active connections above 80"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  metric_namespace    = "Microsoft.DBforPostgreSQL/flexibleServers"
  metric_name         = "active_connections"
  aggregation         = "Average"
  operator            = "GreaterThan"
  threshold           = 80
  action_group_id     = module.action_group.id
  tags                = local.tags
}

module "alert_waf_blocked" {
  source              = "../../modules/monitoring/monitor_metric_alert"
  name                = "alert-waf-blocked-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [module.appgw.id]
  description         = "WAF blocked request spike detected"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  metric_namespace    = "Microsoft.Network/applicationGateways"
  metric_name         = "FirewallBlockedCount"
  aggregation         = "Total"
  operator            = "GreaterThan"
  threshold           = 100
  action_group_id     = module.action_group.id
  tags                = local.tags
}

# --- Diagnostic Settings ---
module "diag_appgw" {
  source                     = "../../modules/monitoring/monitor_diagnostic_setting"
  name                       = "diag-appgw-${local.name_prefix}"
  target_resource_id         = module.appgw.id
  log_analytics_workspace_id = module.law.id
  log_categories = [
    "ApplicationGatewayAccessLog",
    "ApplicationGatewayPerformanceLog",
    "ApplicationGatewayFirewallLog",
  ]
}

module "diag_postgres" {
  source                     = "../../modules/monitoring/monitor_diagnostic_setting"
  name                       = "diag-postgres-${local.name_prefix}"
  target_resource_id         = module.postgres.id
  log_analytics_workspace_id = module.law.id
  log_categories = [
    "PostgreSQLLogs",
  ]
}

module "diag_keyvault" {
  source                     = "../../modules/monitoring/monitor_diagnostic_setting"
  name                       = "diag-kv-${local.name_prefix}"
  target_resource_id         = module.kv.id
  log_analytics_workspace_id = module.law.id
  log_categories = [
    "AuditEvent",
  ]
}
