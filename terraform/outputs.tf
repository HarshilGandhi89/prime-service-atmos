output "vpc_id" {
  value       = module.network.vpc_id
  description = "VPC ID hosting all Prime Service resources."
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.app.repository_url
  description = "Push container images here from CI."
}

output "alb_dns_name" {
  value       = module.compute.alb_dns_name
  description = "Internal ALB hostname. Reachable only via Client VPN."
}

output "client_vpn_endpoint_id" {
  value = module.client_vpn.endpoint_id
}

output "rds_endpoint" {
  value     = module.database.endpoint
  sensitive = true
}

output "deploy_url" {
  value       = "http://${module.compute.alb_dns_name}/api/v1/primes?low=1&high=100"
  description = "Smoke-test URL once a Client VPN session is active."
}
