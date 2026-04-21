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

variable "dev_account_id" {
  description = "AWS account ID for dev environment"
  type        = string
}

variable "prod_account_id" {
  description = "AWS account ID for prod environment"
  type        = string
}
