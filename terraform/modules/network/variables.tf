variable "name_prefix" { type = string }
variable "region_short" { type = string }
variable "vpc_cidr" { type = string }
variable "azs" {
  type        = list(string)
  description = "List of availability zone names (length 2)."
}

variable "enable_flow_logs" {
  type    = bool
  default = true
}

variable "flow_logs_kms_arn" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
