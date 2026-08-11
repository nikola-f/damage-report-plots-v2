variable "app_name" {
  description = "Application name prefix for resource naming (e.g. drp)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string
}

variable "frontend_domain_name" {
  description = "Custom domain for the CloudFront frontend distribution"
  type        = string
  sensitive   = true
}
