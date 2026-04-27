variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
  default     = "damage-report-plots-prod"
}

variable "github_org" {
  description = "GitHub organization or user name"
  type        = string
  default     = "nikola-f"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "damage-report-plots-v2"
}

variable "management_account_id" {
  description = "AWS account ID for the management account"
  type        = string
}

variable "aws_assume_role_arn" {
  description = "ARN of the role to assume for AWS provider (set in CI via TF_VAR_aws_assume_role_arn)"
  type        = string
  default     = ""
}

variable "app_name" {
  description = "Application name prefix for resource naming"
  type        = string
  default     = "drp"
}

variable "api_domain_name" {
  description = "Domain name for ACM certificate (e.g. api.example.com)"
  type        = string
}

variable "rails_master_key_placeholder" {
  description = "Initial placeholder for RAILS_MASTER_KEY in Secrets Manager. Replace manually after first apply."
  type        = string
  sensitive   = true
  default     = "PLACEHOLDER"
}

variable "api_allowed_origins" {
  description = "Comma-separated CORS allowed origins (e.g. https://app.example.com)"
  type        = string
}
