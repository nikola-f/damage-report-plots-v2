resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.name_prefix}-redis"
  subnet_ids = aws_subnet.private[*].id
}

resource "random_password" "redis_auth_token" {
  count   = var.elasticache_replication_enabled ? 1 : 0
  length  = 32
  special = false
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${local.name_prefix}-redis"
  description                = "${local.name_prefix} Valkey"
  node_type                  = var.elasticache_node_type
  engine                     = "valkey"
  engine_version             = "8.0"
  parameter_group_name       = "default.valkey8"
  subnet_group_name          = aws_elasticache_subnet_group.main.name
  security_group_ids         = [aws_security_group.elasticache.id]
  automatic_failover_enabled = var.elasticache_replication_enabled
  num_cache_clusters         = var.elasticache_replication_enabled ? 2 : 1
  transit_encryption_enabled = var.elasticache_replication_enabled
  auth_token                 = var.elasticache_replication_enabled ? random_password.redis_auth_token[0].result : null
  apply_immediately          = true

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }
}
