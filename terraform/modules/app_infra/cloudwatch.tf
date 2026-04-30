resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/${local.name_prefix}-web"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/${local.name_prefix}-worker"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "redis_slow_log" {
  name              = "/elasticache/${local.name_prefix}-slow-log"
  retention_in_days = 30
}
