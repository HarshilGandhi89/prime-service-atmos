# Dev environment values. Pass with:
#   terraform apply -var-file=envs/dev.tfvars

aws_region              = "eu-central-1"
environment             = "dev"
project_prefix          = "atm"
owner                   = "plat"
application             = "prime"
cost_center             = "rd-platform"

vpc_cidr                = "10.50.0.0/16"
client_vpn_cidr         = "10.60.0.0/22"

# ACM ARNs for the Client VPN. Generate locally and import to ACM, then
# place the ARNs here. The repo includes scripts/setup-vpn-client.sh to
# walk through cert generation with `easy-rsa`.
vpn_server_cert_arn      = "arn:aws:acm:eu-central-1:000000000000:certificate/REPLACE-ME-SERVER"
vpn_client_root_cert_arn = "arn:aws:acm:eu-central-1:000000000000:certificate/REPLACE-ME-CLIENT-ROOT"

image_tag               = "dev-latest"

min_tasks               = 1
max_tasks               = 3
task_cpu                = 512
task_memory             = 1024

db_instance_class       = "db.t4g.micro"
db_allocated_storage_gb = 20
db_multi_az             = false
