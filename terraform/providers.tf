# =============================================================================
# Provider + backend configuration
# =============================================================================
# State is stored in S3 with locking via DynamoDB. The bucket / table /
# key prefix are supplied per environment via -backend-config (see envs/
# dev.tfvars and prod.tfvars).
# =============================================================================

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.50" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
  }

  backend "s3" {
    # bucket / key / region / dynamodb_table are passed via
    # `terraform init -backend-config=envs/<env>.backend.hcl`
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "prime-service"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      CostCenter  = var.cost_center
    }
  }
}
