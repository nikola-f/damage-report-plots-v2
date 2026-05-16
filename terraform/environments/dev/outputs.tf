output "gcp_workload_identity_provider" {
  description = "WIF provider name for GitHub Actions secret GCP_WORKLOAD_IDENTITY_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.github_actions.name
  sensitive   = true
}

output "gcp_service_account" {
  description = "Service account email for GitHub Actions secret GCP_SERVICE_ACCOUNT"
  value       = google_service_account.terraform_cicd.email
  sensitive   = true
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.app_infra.ecr_repository_url
  sensitive   = true
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.app_infra.alb_dns_name
  sensitive   = true
}

output "rails_master_key_secret_arn" {
  description = "Secrets Manager ARN for RAILS_MASTER_KEY — set the real value after first apply"
  value       = module.app_infra.rails_master_key_secret_arn
  sensitive   = true
}

output "redis_url_secret_arn" {
  description = "Secrets Manager ARN for REDIS_URL"
  value       = module.app_infra.redis_url_secret_arn
  sensitive   = true
}

output "google_client_id_secret_arn" {
  description = "Secrets Manager ARN for GOOGLE_CLIENT_ID"
  value       = module.app_infra.google_client_id_secret_arn
  sensitive   = true
}

output "google_client_secret_secret_arn" {
  description = "Secrets Manager ARN for GOOGLE_CLIENT_SECRET"
  value       = module.app_infra.google_client_secret_secret_arn
  sensitive   = true
}

output "web_target_group_arn" {
  value     = module.app_infra.web_target_group_arn
  sensitive = true
}

output "task_execution_role_arn" {
  value     = module.app_infra.task_execution_role_arn
  sensitive = true
}

output "task_role_arn" {
  value     = module.app_infra.task_role_arn
  sensitive = true
}

output "private_subnet_ids_csv" {
  value     = module.app_infra.private_subnet_ids_csv
  sensitive = true
}

output "public_subnet_ids_csv" {
  value     = module.app_infra.public_subnet_ids_csv
  sensitive = true
}

output "ecs_security_group_id" {
  value     = module.app_infra.ecs_security_group_id
  sensitive = true
}

output "log_group_web" {
  value     = module.app_infra.log_group_web
  sensitive = true
}

output "log_group_worker" {
  value     = module.app_infra.log_group_worker
  sensitive = true
}

output "redis_url" {
  value     = module.app_infra.redis_url
  sensitive = true
}

output "sqs_thread_ids_queue_url" {
  value     = module.app_infra.sqs_thread_ids_queue_url
  sensitive = true
}

output "sqs_reports_queue_url" {
  value     = module.app_infra.sqs_reports_queue_url
  sensitive = true
}

output "allowed_origins" {
  value = module.app_infra.allowed_origins
}

output "aws_region" {
  value = module.app_infra.aws_region
}

output "frontend_bucket_name" {
  value     = module.app_infra.frontend_bucket_name
  sensitive = true
}

output "frontend_cloudfront_domain" {
  description = "Set as authorized redirect URI in Google Cloud Console: https://<domain>/auth/google_oauth2/callback"
  value       = module.app_infra.frontend_cloudfront_domain
  sensitive   = true
}

output "frontend_cloudfront_distribution_id" {
  value     = module.app_infra.frontend_cloudfront_distribution_id
  sensitive = true
}

