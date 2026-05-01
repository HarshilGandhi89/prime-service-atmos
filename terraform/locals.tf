# Naming follows the playbook's convention:
#   [orgprefix]-[owner]-[application]-[env]-[resource]-[location]
# e.g. atm-plat-prime-dev-vpc-euc1
locals {
  short_region = replace(replace(var.aws_region, "-", ""), "central", "c")
  name_prefix  = "${var.project_prefix}-${var.owner}-${var.application}-${var.environment}"
  region_short = local.short_region

  common_tags = {
    Application = var.application
    Environment = var.environment
    Owner       = var.owner
  }
}
