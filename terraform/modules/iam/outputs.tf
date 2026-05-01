output "ecs_task_role_arn" { value = aws_iam_role.task.arn }
output "ecs_task_execution_role_arn" { value = aws_iam_role.task_execution.arn }
output "developers_group" { value = aws_iam_group.developers.name }
output "devops_group" { value = aws_iam_group.devops.name }
output "admins_group" { value = aws_iam_group.admins.name }
