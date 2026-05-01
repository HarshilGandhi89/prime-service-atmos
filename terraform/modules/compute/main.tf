# =============================================================================
# Compute module: ECS Fargate cluster + service + internal ALB
# =============================================================================
# Topology:
#
#   Client VPN peer
#         │  10.60.0.0/22
#         ▼
#   ┌──────────────┐  443/80    ┌──────────────────┐  8080
#   │ Internal ALB │───────────▶│  ECS Fargate svc │──────▶ RDS Postgres
#   │  (private)   │            │   (2-6 tasks)    │
#   └──────────────┘            └──────────────────┘
#
# Security groups (least-privilege):
#   sg-alb     : ingress 80/443 from VPC CIDR only.
#   sg-task    : ingress 8080 from sg-alb only.
#   sg-db      : ingress 5432 from sg-task only (defined in db module).
# =============================================================================

# ---------- CloudWatch log group ----------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/ecs/${var.name_prefix}/api"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ---------- ECS cluster ----------
resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-ecs"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

# ---------- Security groups ----------
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-sg-alb"
  description = "Internal ALB for ${var.name_prefix}"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-sg-alb" })
}

resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  description       = "HTTPS from inside the VPC (incl. Client VPN pool routed in)"
  security_group_id = aws_security_group.alb.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.this.cidr_block]
}

resource "aws_security_group_rule" "alb_egress" {
  type              = "egress"
  security_group_id = aws_security_group.alb.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group" "task" {
  name        = "${var.name_prefix}-sg-task"
  description = "Fargate tasks for ${var.name_prefix}"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-sg-task" })
}

resource "aws_security_group_rule" "task_ingress_from_alb" {
  type                     = "ingress"
  description              = "Tasks accept 8080 from ALB only"
  security_group_id        = aws_security_group.task.id
  source_security_group_id = aws_security_group.alb.id
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
}

resource "aws_security_group_rule" "task_egress" {
  type              = "egress"
  security_group_id = aws_security_group.task.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

# ---------- Internal ALB ----------
resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = var.private_subnet_ids
  security_groups    = [aws_security_group.alb.id]
  idle_timeout       = 60
  drop_invalid_header_fields = true

  tags = var.tags
}

resource "aws_lb_target_group" "api" {
  name        = "${var.name_prefix}-tg-api"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 20
  tags                 = var.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# Listener on 443 with ACM cert is recommended for prod; left to ops to attach
# var.alb_certificate_arn once issued.

# ---------- Task definition ----------
resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name_prefix}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = "${var.ecr_repository_url}:${var.image_tag}"
      essential = true
      portMappings = [{
        containerPort = 8080
        protocol      = "tcp"
      }]
      environment = [
        { name = "LOG_LEVEL", value = "INFO" },
        { name = "PRIME_MAX_RANGE", value = "10000000" },
      ]
      secrets = [
        # Build the URL from Secrets Manager parts at task start.
        { name = "DATABASE_URL_RAW", valueFrom = var.db_secret_arn },
      ]
      command = [
        "sh", "-c",
        # Compose DATABASE_URL from the JSON secret, then exec uvicorn.
        join(" ", [
          "export DATABASE_URL=\"postgresql+psycopg2://$(echo $DATABASE_URL_RAW | python -c 'import sys,json;d=json.loads(sys.stdin.read());print(d[\"username\"]+\":\"+d[\"password\"]+\"@${var.db_endpoint}:5432/\"+d[\"dbname\"])')\";",
          "exec uvicorn src.main:app --host 0.0.0.0 --port 8080"
        ])
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "api"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "python -c 'import urllib.request,sys;sys.exit(0 if urllib.request.urlopen(\"http://127.0.0.1:8080/healthz\").status==200 else 1)'"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }
      readonlyRootFilesystem = false
    }
  ])

  tags = var.tags
}

data "aws_region" "current" {}

# ---------- ECS Service ----------
resource "aws_ecs_service" "api" {
  name            = "${var.name_prefix}-svc-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  propagate_tags  = "SERVICE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http]
  tags       = var.tags
}

# ---------- Auto-scaling ----------
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_tasks
  min_capacity       = var.min_tasks
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name_prefix}-cpu-scale"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_in_cooldown  = 60
    scale_out_cooldown = 30
  }
}
