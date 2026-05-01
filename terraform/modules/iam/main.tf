# =============================================================================
# IAM module
# =============================================================================
# Mirrors the playbook's "groups -> role mapping" pattern from §1.4. Two
# concerns:
#
#  1) Human IAM groups (developer, devops, admin) created with least-privilege
#     starting points. Operators are expected to be added to the appropriate
#     group via SSO/AD federation; no individual policy attachments.
#
#  2) Service identities for the workload:
#       * task_execution_role -- pulls images from ECR, reads RDS secret,
#         writes CloudWatch logs.
#       * task_role           -- runtime identity assumed by the app.
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Human groups
# -----------------------------------------------------------------------------
resource "aws_iam_group" "developers" {
  name = "${var.name_prefix}-grp-developers"
}

resource "aws_iam_group_policy_attachment" "developers_readonly" {
  group      = aws_iam_group.developers.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_group" "devops" {
  name = "${var.name_prefix}-grp-devops"
}

# Devops group: deploy CI artifacts, restart ECS, read DB secret. No raw IAM.
resource "aws_iam_policy" "devops" {
  name = "${var.name_prefix}-pol-devops"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrReadWrite"
        Effect   = "Allow"
        Action   = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
        ]
        Resource = [var.ecr_repo_arn, "${var.ecr_repo_arn}/*", "*"]
      },
      {
        Sid    = "EcsDeploy"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:ListTasks",
        ]
        Resource = "*"
      },
      {
        Sid      = "ReadDbSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = var.db_secret_arn
      },
    ]
  })
}

resource "aws_iam_group_policy_attachment" "devops" {
  group      = aws_iam_group.devops.name
  policy_arn = aws_iam_policy.devops.arn
}

resource "aws_iam_group" "admins" {
  name = "${var.name_prefix}-grp-admins"
}

resource "aws_iam_group_policy_attachment" "admin_admin" {
  group      = aws_iam_group.admins.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# -----------------------------------------------------------------------------
# 2. ECS roles
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.name_prefix}-role-task-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "task_exec_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "task_exec_secrets" {
  name = "${var.name_prefix}-pol-task-exec-secrets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.db_secret_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_exec_secrets" {
  role       = aws_iam_role.task_execution.name
  policy_arn = aws_iam_policy.task_exec_secrets.arn
}

# Task role -- runtime identity. Empty policy by default; extend if the app
# needs to call AWS APIs (e.g., publish to SNS).
resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-role-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}
