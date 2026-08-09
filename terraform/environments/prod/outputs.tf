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

output "public_subnet_ids_csv" {
  value     = module.app_infra.public_subnet_ids_csv
  sensitive = true
}

output "ipv6_subnet_ids_csv" {
  value     = module.app_infra.ipv6_subnet_ids_csv
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
  value     = module.app_infra.frontend_cloudfront_domain
  sensitive = true
}

output "frontend_cloudfront_distribution_id" {
  value     = module.app_infra.frontend_cloudfront_distribution_id
  sensitive = true
}
