variable "name" {}
variable "location" {}
variable "resource_group_name" {}
variable "subnet_id" {}
variable "tags" { type = map(string) }

variable "firewall_policy_id" {
  type    = string
  default = null
}

variable "sku_name" {
  type    = string
  default = "WAF_v2"
}

variable "sku_tier" {
  type    = string
  default = "WAF_v2"
}

variable "autoscale_min" {
  type    = number
  default = 1
}

variable "autoscale_max" {
  type    = number
  default = 3
}

variable "gateway_ip_config_name" {
  type    = string
  default = "gateway-ip"
}

variable "frontend_ip_configurations" {
  description = "List of frontend IP configurations"
  type = list(object({
    name                 = string
    public_ip_address_id = string
  }))
}

variable "frontend_ports" {
  description = "List of frontend ports"
  type = list(object({
    name = string
    port = number
  }))
}

variable "backend_address_pools" {
  description = "List of backend address pools"
  type = list(object({
    name  = string
    fqdns = list(string)
  }))
}

variable "backend_http_settings" {
  description = "List of backend HTTP settings"
  type = list(object({
    name                                = string
    cookie_based_affinity               = string
    port                                = number
    protocol                            = string
    request_timeout                     = number
    pick_host_name_from_backend_address = bool
    probe_name                          = optional(string)
  }))
}

variable "health_probes" {
  description = "List of health probes"
  type = list(object({
    name                                      = string
    protocol                                  = string
    path                                      = string
    interval                                  = number
    timeout                                   = number
    unhealthy_threshold                       = number
    pick_host_name_from_backend_http_settings = bool
  }))
  default = []
}

variable "http_listeners" {
  description = "List of HTTP listeners"
  type = list(object({
    name                           = string
    frontend_ip_configuration_name = string
    frontend_port_name             = string
    protocol                       = string
  }))
}

variable "redirect_configurations" {
  description = "List of redirect configurations"
  type = list(object({
    name                 = string
    redirect_type        = string
    target_listener_name = string
    include_path         = bool
    include_query_string = bool
  }))
  default = []
}

variable "request_routing_rules" {
  description = "List of request routing rules"
  type = list(object({
    name                        = string
    priority                    = number
    rule_type                   = string
    http_listener_name          = string
    backend_address_pool_name   = optional(string)
    backend_http_settings_name  = optional(string)
    redirect_configuration_name = optional(string)
  }))
}
