resource "aws_elasticache_serverless_cache" "main" {
  engine = "valkey"
  name   = "${local.name_prefix}-valkey"

  cache_usage_limits {
    data_storage {
      maximum = 1
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 1000
    }
  }

  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.elasticache.id]

  major_engine_version = "8"
}
