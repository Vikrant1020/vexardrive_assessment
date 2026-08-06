variable "name" {}
variable "container_app_environment_id" {}
variable "resource_group_name" {}
variable "acr_login_server" {}
variable "container_image" { default = "" }
variable "container_cpu" {}
variable "container_memory" {}
variable "container_min_replicas" {}
variable "container_max_replicas" {}
variable "environment" {}
variable "tags" { type = map(string) }

variable "identity_ids" {
  description = "List of User Assigned Identity resource IDs"
  type        = list(string)
}

variable "container_secrets" {
  description = "List of secrets for the container app"
  type = list(object({
    name                = string
    value               = optional(string)
    key_vault_secret_id = optional(string)
    identity            = optional(string)
  }))
  default = []
}

variable "environment_variables" {
  description = "List of environment variables for the container"
  type = list(object({
    name        = string
    value       = optional(string)
    secret_name = optional(string)
  }))
  default = []
}

variable "revision_mode" {
  type = string
}

variable "workload_profile_name" {
  type = string
}

variable "target_port" {
  type = number
}