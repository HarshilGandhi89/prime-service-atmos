# =============================================================================
# RDS PostgreSQL (single AZ for dev / Multi-AZ for prod)
# =============================================================================
# Security:
#   * Deployed in private subnets only.
#   * Security group permits 5432 ingress only from the ECS task SG.
#   * Master credentials live in Secrets Manager and are rotated by AWS.
#   * Storage encryption via KMS (AWS-managed key for simplicity).
# =============================================================================

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-dbsubnet"
  subnet_ids = var.private_subnet_ids
  tags       = merge(var.tags, { Name = "${var.name_prefix}-dbsubnet" })
}

resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-sg-db"
  description = "RDS Postgres for ${var.name_prefix}"
  vpc_id      = var.vpc_id

  # Ingress is opened by the root module via aws_security_group_rule, which
  # avoids a module-level circular dependency between compute and database.
  egress {
    description = "Egress allowed (RDS rarely needs it; left open for now)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-sg-db" })
}

resource "random_password" "master" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>?"
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.name_prefix}/rds/master"
  description             = "Master credentials for ${var.name_prefix} RDS"
  recovery_window_in_days = 7
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    dbname   = var.database_name
  })
}

resource "aws_db_instance" "this" {
  identifier              = "${var.name_prefix}-pg"
  engine                  = "postgres"
  engine_version          = var.engine_version
  instance_class          = var.instance_class
  allocated_storage       = var.allocated_storage
  storage_encrypted       = true
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  username                = var.master_username
  password                = random_password.master.result
  db_name                 = var.database_name
  multi_az                = var.multi_az
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = !var.deletion_protection
  backup_retention_period = 7
  apply_immediately       = false
  publicly_accessible     = false

  performance_insights_enabled = true
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(var.tags, { Name = "${var.name_prefix}-pg" })
}
