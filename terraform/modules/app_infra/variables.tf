variable "app_name" {
  description = "Application name prefix for resource naming (e.g. drp)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "domain_name" {
  description = "Domain name for ACM certificate (e.g. api.dev.example.com)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (2 required for ALB)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones (must be 2)"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}


variable "rails_master_key_placeholder" {
  description = "Initial placeholder value for RAILS_MASTER_KEY in Secrets Manager. Replace manually after first apply."
  type        = string
  sensitive   = true
  default     = "PLACEHOLDER"
}

variable "allowed_origins" {
  description = "Comma-separated CORS allowed origins (e.g. https://app.example.com)"
  type        = string
}

variable "frontend_domain_name" {
  description = "Custom domain for the CloudFront frontend distribution"
  type        = string
  sensitive   = true
}

# Per-environment Settings tuning values. No defaults: each environment must set
# them explicitly in its module block so dev and prod can diverge.
variable "thread_batch_worker_poll_interval" {
  description = "Seconds between GmailThreadBatchWorker polling cycles"
  type        = number
}

variable "thread_batch_worker_lock_ttl" {
  description = "Redis lock TTL in seconds for GmailThreadBatchWorker"
  type        = number
}

variable "thread_batch_worker_max_messages_per_run" {
  description = "Max SQS messages processed per GmailThreadBatchWorker run"
  type        = number
}

variable "spreadsheet_sync_worker_poll_interval" {
  description = "Seconds between SpreadsheetSyncWorker polling cycles"
  type        = number
}

variable "spreadsheet_sync_worker_lock_ttl" {
  description = "Redis lock TTL in seconds for SpreadsheetSyncWorker"
  type        = number
}

variable "thread_list_worker_threads_per_message" {
  description = "Thread IDs per SQS message for GmailThreadListWorker"
  type        = number
}

variable "thread_batch_fetcher_batch_size" {
  description = "Number of thread IDs per Gmail Batch API request in GmailThreadBatchFetcher"
  type        = number
}

variable "thread_batch_fetcher_inter_batch_sleep" {
  description = "Seconds to sleep between batch API calls in GmailThreadBatchFetcher"
  type        = number
}

variable "thread_list_worker_thread_id_limit" {
  description = "Max thread IDs collected before GmailThreadListWorker stops looping"
  type        = number
}

variable "spreadsheet_sync_worker_max_messages_per_run" {
  description = "Max SQS messages processed per SpreadsheetSyncWorker run"
  type        = number
}

variable "sync_min_interval" {
  description = "Minimum seconds between syncs per user; POST /api/v1/sync returns 429 within this window"
  type        = number
}
