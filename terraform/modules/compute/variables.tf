variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "ecr_repository_url" { type = string }

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "task_cpu" {
  type    = number
  default = 512
}

variable "task_memory" {
  type    = number
  default = 1024
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "min_tasks" {
  type    = number
  default = 2
}

variable "max_tasks" {
  type    = number
  default = 6
}

variable "task_role_arn" { type = string }
variable "task_execution_role_arn" { type = string }
variable "db_secret_arn" { type = string }
variable "db_endpoint" { type = string }

variable "db_name" {
  type    = string
  default = "primes"
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
