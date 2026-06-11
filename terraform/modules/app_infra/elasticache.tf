resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.name_prefix}-valkey"
  subnet_ids = aws_subnet.app_ipv6[*].id
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${local.name_prefix}-valkey"
  description          = "Valkey for ${local.name_prefix}"

  engine             = "valkey"
  engine_version     = "8.0"
  node_type          = "cache.t4g.micro"
  num_cache_clusters = 1

  # IPv6 so IPv6-only ECS tasks can reach the cache
  network_type = "ipv6"
  ip_discovery = "ipv6"

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.elasticache.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  snapshot_retention_limit = 1
  snapshot_window          = "21:00-22:00"

  apply_immediately = true

  tags = {
    Name = "${local.name_prefix}-valkey"
  }
}
