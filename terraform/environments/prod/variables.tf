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

# Not marked sensitive: this is the address users type. It is on the OAuth
# consent screen, in Search Console and in the privacy policy, so secrecy would
# be a fiction — and it would redact every plan diff that touches ACM or
# CloudFront, including the DNS records the certificate needs published.
variable "frontend_domain_name" {
  description = "Custom domain for the CloudFront frontend distribution"
  type        = string

  # An unset GitHub variable arrives as TF_VAR_frontend_domain_name="", which
  # Terraform accepts as a real value rather than a missing one. That would
  # replace the ACM certificate and strip the CloudFront alias, so refuse it
  # here instead.
  validation {
    condition     = length(var.frontend_domain_name) > 0
    error_message = "frontend_domain_name must not be empty."
  }
}
