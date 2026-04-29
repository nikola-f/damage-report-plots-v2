output "gcp_workload_identity_provider" {
  description = "WIF provider name for GitHub Actions secret GCP_WORKLOAD_IDENTITY_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.github_actions.name
}

output "gcp_service_account" {
  description = "Service account email for GitHub Actions secret GCP_SERVICE_ACCOUNT"
  value       = google_service_account.terraform_cicd.email
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.app_infra.ecr_repository_url
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.app_infra.alb_dns_name
}

output "acm_validation_records" {
  description = "DNS CNAME records required to validate the ACM certificate"
  value       = module.app_infra.acm_validation_records
}

output "rails_master_key_secret_arn" {
  description = "Secrets Manager ARN for RAILS_MASTER_KEY — set the real value after first apply"
  value       = module.app_infra.rails_master_key_secret_arn
}
