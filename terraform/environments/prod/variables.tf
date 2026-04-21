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
