# Prod environment values.
aws_region              = "eu-central-1"
environment             = "prod"
project_prefix          = "atm"
owner                   = "plat"
application             = "prime"
cost_center             = "ops-platform"

vpc_cidr                = "10.51.0.0/16"
client_vpn_cidr         = "10.61.0.0/22"

vpn_server_cert_arn      = "arn:aws:acm:eu-central-1:000000000000:certificate/REPLACE-ME-PROD-SERVER"
vpn_client_root_cert_arn = "arn:aws:acm:eu-central-1:000000000000:certificate/REPLACE-ME-PROD-CLIENT-ROOT"

image_tag               = "prod-latest"

min_tasks               = 2
max_tasks               = 8
task_cpu                = 1024
task_memory             = 2048

db_instance_class       = "db.t4g.medium"
db_allocated_storage_gb = 100
db_multi_az             = true
