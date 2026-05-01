# =============================================================================
# Root composition for the Prime Service environment
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# Networking: VPC, public + private subnets, NAT, route tables, flow logs
# -----------------------------------------------------------------------------
module "network" {
  source = "./modules/network"

  name_prefix       = local.name_prefix
  region_short      = local.region_short
  vpc_cidr          = var.vpc_cidr
  azs               = slice(data.aws_availability_zones.available.names, 0, 2)
  enable_flow_logs  = true
  flow_logs_kms_arn = null # set in prod
}

# -----------------------------------------------------------------------------
# Container registry
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "app" {
  name                 = "${local.name_prefix}-ecr"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 30 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 30
        }
        action = { type = "expire" }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Database: RDS PostgreSQL in private subnets
# -----------------------------------------------------------------------------
module "database" {
  source = "./modules/database"

  name_prefix         = local.name_prefix
  vpc_id              = module.network.vpc_id
  private_subnet_ids  = module.network.private_subnet_ids
  instance_class      = var.db_instance_class
  allocated_storage   = var.db_allocated_storage_gb
  multi_az            = var.db_multi_az
  database_name       = "primes"
  master_username     = "prime"
  deletion_protection = var.environment == "prod"

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# IAM: groups + roles for human and machine identities
# -----------------------------------------------------------------------------
module "iam" {
  source = "./modules/iam"

  name_prefix = local.name_prefix
  ecr_repo_arn = aws_ecr_repository.app.arn
  db_secret_arn = module.database.master_secret_arn

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Compute: ECS Fargate cluster, service, internal ALB
# -----------------------------------------------------------------------------
module "compute" {
  source = "./modules/compute"

  name_prefix          = local.name_prefix
  vpc_id               = module.network.vpc_id
  private_subnet_ids   = module.network.private_subnet_ids
  ecr_repository_url   = aws_ecr_repository.app.repository_url
  image_tag            = var.image_tag
  task_cpu             = var.task_cpu
  task_memory          = var.task_memory
  desired_count        = var.min_tasks
  min_tasks            = var.min_tasks
  max_tasks            = var.max_tasks
  task_role_arn        = module.iam.ecs_task_role_arn
  task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  db_secret_arn        = module.database.master_secret_arn
  db_endpoint          = module.database.endpoint
  db_name              = module.database.db_name
  log_retention_days   = 30

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Wire the task SG -> DB SG ingress at the root level to avoid a circular
# dependency between the compute and database modules.
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "db_ingress_from_task" {
  type                     = "ingress"
  description              = "Postgres from ECS tasks only"
  security_group_id        = module.database.security_group_id
  source_security_group_id = module.compute.task_security_group_id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
}

# -----------------------------------------------------------------------------
# Client VPN endpoint - only ingress path
# -----------------------------------------------------------------------------
module "client_vpn" {
  source = "./modules/client_vpn"

  name_prefix              = local.name_prefix
  vpc_id                   = module.network.vpc_id
  client_cidr_block        = var.client_vpn_cidr
  associated_subnet_ids    = module.network.private_subnet_ids
  server_certificate_arn   = var.vpn_server_cert_arn
  client_root_cert_arn     = var.vpn_client_root_cert_arn
  vpc_cidr_to_authorize    = var.vpc_cidr
  log_retention_days       = 90

  tags = local.common_tags
}
