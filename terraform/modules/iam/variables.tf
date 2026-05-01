variable "name_prefix" { type = string }
variable "ecr_repo_arn" { type = string }
variable "db_secret_arn" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}
