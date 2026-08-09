output "public_subnet_ids_csv" {
  description = "Public subnet IDs as a comma-separated string"
  value       = join(",", aws_subnet.public[*].id)
}

output "ipv6_subnet_ids_csv" {
  description = "IPv6-only subnet IDs as a comma-separated string"
  value       = join(",", aws_subnet.app_ipv6[*].id)
}

output "allowed_origins" {
  description = "CORS allowed origins"
  value       = var.allowed_origins
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "frontend_bucket_name" {
  description = "S3 bucket name for frontend static files"
  value       = aws_s3_bucket.frontend.bucket
}

output "frontend_cloudfront_domain" {
  description = "CloudFront distribution domain name for the frontend"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "frontend_cloudfront_distribution_id" {
  description = "CloudFront distribution ID (used for cache invalidation on deploy)"
  value       = aws_cloudfront_distribution.frontend.id
}

output "frontend_acm_validation_records" {
  description = "DNS CNAME records required to validate the frontend ACM certificate (us-east-1)"
  sensitive   = true
  value = {
    for dvo in aws_acm_certificate.frontend.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
}
