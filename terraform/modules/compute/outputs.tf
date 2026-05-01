output "cluster_name" { value = aws_ecs_cluster.this.name }
output "service_name" { value = aws_ecs_service.api.name }
output "task_security_group_id" { value = aws_security_group.task.id }
output "alb_dns_name" { value = aws_lb.this.dns_name }
output "alb_arn" { value = aws_lb.this.arn }
output "target_group_arn" { value = aws_lb_target_group.api.arn }
