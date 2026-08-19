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

# Keeps `sensitive`: the bucket name embeds the AWS account id.
output "frontend_bucket_name" {
  value     = module.app_infra.frontend_bucket_name
  sensitive = true
}

output "frontend_cloudfront_domain" {
  value = module.app_infra.frontend_cloudfront_domain
}

output "frontend_cloudfront_distribution_id" {
  value = module.app_infra.frontend_cloudfront_distribution_id
}

# DNS records to create when the frontend ACM certificate is first issued;
# without them the certificate never validates and CloudFront cannot serve the
# custom domain. Re-exported because module outputs are not reachable from the
# root otherwise.
output "frontend_acm_validation_records" {
  value = module.app_infra.frontend_acm_validation_records
}
