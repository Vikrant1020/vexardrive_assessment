variable "name" {}
variable "resource_group_name" {}
variable "scopes" { type = list(string) }
variable "description" {}
variable "severity" {}
variable "frequency" {}
variable "window_size" {}
variable "metric_namespace" {}
variable "metric_name" {}
variable "aggregation" {}
variable "operator" {}
variable "threshold" {}
variable "action_group_id" {}
variable "dimension_name" { default = "" }
variable "dimension_values" { default = [] }
variable "tags" { type = map(string) }
