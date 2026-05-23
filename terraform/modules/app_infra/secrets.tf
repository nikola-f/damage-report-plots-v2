resource "aws_secretsmanager_secret" "rails_master_key" {
  name        = "${var.app_name}/${var.environment}/rails-master-key"
  description = "RAILS_MASTER_KEY for ${local.name_prefix}"
}

resource "aws_secretsmanager_secret_version" "rails_master_key" {
  secret_id     = aws_secretsmanager_secret.rails_master_key.id
  secret_string = var.rails_master_key_placeholder
}

resource "aws_secretsmanager_secret" "google_client_id" {
  name        = "${var.app_name}/${var.environment}/google-client-id"
  description = "Google OAuth client ID for ${local.name_prefix}"
}

resource "aws_secretsmanager_secret_version" "google_client_id" {
  secret_id     = aws_secretsmanager_secret.google_client_id.id
  secret_string = "placeholder"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "google_client_secret" {
  name        = "${var.app_name}/${var.environment}/google-client-secret"
  description = "Google OAuth client secret for ${local.name_prefix}"
}

resource "aws_secretsmanager_secret_version" "google_client_secret" {
  secret_id     = aws_secretsmanager_secret.google_client_secret.id
  secret_string = "placeholder"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "redis_url" {
  name        = "${var.app_name}/${var.environment}/redis-url"
  description = "REDIS_URL for ${local.name_prefix}"
}

resource "aws_secretsmanager_secret_version" "redis_url" {
  secret_id     = aws_secretsmanager_secret.redis_url.id
  secret_string = "rediss://${aws_elasticache_replication_group.main.primary_endpoint_address}:6379/0"
}
