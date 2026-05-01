variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "client_cidr_block" { type = string }
variable "associated_subnet_ids" { type = list(string) }
variable "server_certificate_arn" { type = string }
variable "client_root_cert_arn" { type = string }
variable "vpc_cidr_to_authorize" { type = string }

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "tags" {
  type    = map(string)
  default = {}
}
