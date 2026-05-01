# =============================================================================
# AWS Client VPN endpoint
# =============================================================================
# This is the cloud equivalent of the WireGuard gateway used in docker-compose.
# Authentication uses mutual-TLS (server cert + client root CA). For SAML/SSO,
# swap `authentication_options.type` to "federated-authentication" and supply
# `saml_provider_arn`.
# =============================================================================

resource "aws_cloudwatch_log_group" "vpn" {
  name              = "/aws/clientvpn/${var.name_prefix}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_cloudwatch_log_stream" "vpn" {
  name           = "connection-log"
  log_group_name = aws_cloudwatch_log_group.vpn.name
}

resource "aws_security_group" "vpn" {
  name        = "${var.name_prefix}-sg-vpn"
  description = "Client VPN endpoint ENI security group"
  vpc_id      = var.vpc_id

  egress {
    description = "Forward into the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-sg-vpn" })
}

resource "aws_ec2_client_vpn_endpoint" "this" {
  description            = "${var.name_prefix} client VPN"
  server_certificate_arn = var.server_certificate_arn
  client_cidr_block      = var.client_cidr_block
  split_tunnel           = true
  vpc_id                 = var.vpc_id
  security_group_ids     = [aws_security_group.vpn.id]
  transport_protocol     = "udp"
  vpn_port               = 443

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = var.client_root_cert_arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.vpn.name
  }

  dns_servers = ["169.254.169.253"] # AmazonProvidedDNS

  tags = merge(var.tags, { Name = "${var.name_prefix}-cvpn" })
}

# Associate the endpoint with each private subnet (one association per AZ).
resource "aws_ec2_client_vpn_network_association" "this" {
  for_each               = toset(var.associated_subnet_ids)
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  subnet_id              = each.value
}

# Authorize peers to reach the workload VPC CIDR.
resource "aws_ec2_client_vpn_authorization_rule" "vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  target_network_cidr    = var.vpc_cidr_to_authorize
  authorize_all_groups   = true
  description            = "Authorize all enrolled peers to reach the VPC"
}
