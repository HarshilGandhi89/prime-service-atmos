output "endpoint_id" { value = aws_ec2_client_vpn_endpoint.this.id }
output "dns_name" { value = aws_ec2_client_vpn_endpoint.this.dns_name }
output "security_group_id" { value = aws_security_group.vpn.id }
