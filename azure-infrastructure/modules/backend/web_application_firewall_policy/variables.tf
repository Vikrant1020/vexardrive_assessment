variable "name" {}
variable "location" {}
variable "resource_group_name" {}
variable "tags" { type = map(string) }

variable "policy_enabled" {
  type    = bool
  default = true
}

variable "policy_mode" {
  type    = string
  default = "Prevention"
}

variable "request_body_check" {
  type    = bool
  default = true
}

variable "max_request_body_size_in_kb" {
  type    = number
  default = 128
}

variable "file_upload_limit_in_mb" {
  type    = number
  default = 10
}

variable "managed_rule_sets" {
  description = "List of managed rule sets to apply"
  type = list(object({
    type    = string
    version = string
  }))
  default = [
    { type = "OWASP", version = "3.2" },
    { type = "Microsoft_BotManagerRuleSet", version = "1.0" },
  ]
}
