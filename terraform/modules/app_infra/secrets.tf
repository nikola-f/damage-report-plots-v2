resource "aws_secretsmanager_secret" "rails_master_key" {
  name        = "${var.app_name}/${var.environment}/rails-master-key"
  description = "RAILS_MASTER_KEY for ${local.name_prefix}"
}

resource "aws_secretsmanager_secret_version" "rails_master_key" {
  secret_id     = aws_secretsmanager_secret.rails_master_key.id
  secret_string = var.rails_master_key_placeholder
}

resource "aws_secretsmanager_secret" "redis_url" {
  name        = "${var.app_name}/${var.environment}/redis-url"
  description = "REDIS_URL for ${local.name_prefix}"
}

resource "aws_secretsmanager_secret_version" "redis_url" {
  secret_id     = aws_secretsmanager_secret.redis_url.id
  secret_string = "rediss://${aws_elasticache_serverless_cache.main.endpoint[0].address}:6379/0"
}
