# =============================================================================
# Top-level variables for the Prime Service deployment
# =============================================================================

variable "aws_region" {
  type        = string
  description = "AWS region (e.g. eu-central-1, us-east-1)."
  default     = "eu-central-1"
}

variable "environment" {
  type        = string
  description = "dev | qa | prod"
  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment must be one of dev, qa, prod"
  }
}

# Naming-convention tokens (mirrors the playbook's
#   [orgprefix]-[owner]-[env]-[application]-[resource]-[location] pattern)
variable "project_prefix" {
  type        = string
  description = "Org prefix, e.g. atm (ATMOS)."
  default     = "atm"
}

variable "owner" {
  type        = string
  description = "Team / business unit, e.g. plat (platform)."
  default     = "plat"
}

variable "application" {
  type        = string
  description = "Application name, e.g. prime."
  default     = "prime"
}

variable "cost_center" {
  type    = string
  default = "rd-platform"
}

# ---- Networking ----
variable "vpc_cidr" {
  type        = string
  default     = "10.50.0.0/16"
  description = "Top-level VPC CIDR. Subnets are derived deterministically."
}

variable "client_vpn_cidr" {
  type        = string
  default     = "10.60.0.0/22"
  description = "Address pool that AWS Client VPN assigns to peers. Must NOT overlap vpc_cidr."
}

variable "vpn_server_cert_arn" {
  type        = string
  description = "ACM ARN of the server certificate for AWS Client VPN."
}

variable "vpn_client_root_cert_arn" {
  type        = string
  description = "ACM ARN of the client root CA for mutual auth (AWS Client VPN)."
}

# ---- Application ----
variable "image_tag" {
  type        = string
  description = "ECR image tag to deploy (set by CI from git sha)."
  default     = "latest"
}

variable "min_tasks" {
  type    = number
  default = 2
}

variable "max_tasks" {
  type    = number
  default = 6
}

variable "task_cpu" {
  type        = number
  default     = 512 # 0.5 vCPU
  description = "Fargate CPU units."
}

variable "task_memory" {
  type        = number
  default     = 1024
  description = "Fargate memory (MiB)."
}

# ---- Database ----
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage_gb" {
  type    = number
  default = 20
}

variable "db_multi_az" {
  type    = bool
  default = false
}
