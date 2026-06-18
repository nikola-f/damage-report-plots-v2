output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = aws_iam_role.ecs_execution.arn
}

output "task_role_arn" {
  description = "ECS task role ARN"
  value       = aws_iam_role.ecs_task.arn
}

output "web_target_group_arn" {
  description = "ALB target group ARN for the web service"
  value       = aws_lb_target_group.web.arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "public_subnet_ids_csv" {
  description = "Public subnet IDs as a comma-separated string (for ecspresso jsonnet std.split)"
  value       = join(",", aws_subnet.public[*].id)
}

output "ipv6_subnet_ids_csv" {
  description = "IPv6-only subnet IDs as a comma-separated string (for ECS tasks via ecspresso jsonnet std.split)"
  value       = join(",", aws_subnet.app_ipv6[*].id)
}

output "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs_tasks.id
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.api.repository_url
}

output "ecr_repository_url_dualstack" {
  description = "ECR repository URL using dual-stack endpoint (IPv6 compatible)"
  value = replace(
    replace(aws_ecr_repository.api.repository_url, ".dkr.ecr.", ".dkr-ecr."),
    ".amazonaws.com",
    ".on.aws"
  )
}

output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.api.arn
}

output "log_group_web" {
  description = "CloudWatch log group name for web service"
  value       = aws_cloudwatch_log_group.web.name
}

output "log_group_worker" {
  description = "CloudWatch log group name for worker service"
  value       = aws_cloudwatch_log_group.worker.name
}

output "redis_url" {
  description = "Valkey connection URL"
  sensitive   = true
  value       = "rediss://${aws_elasticache_replication_group.main.primary_endpoint_address}:6379/0"
}

output "sqs_thread_ids_queue_url" {
  description = "SQS FIFO queue URL for thread IDs"
  value       = aws_sqs_queue.thread_ids.url
}

output "sqs_reports_queue_url" {
  description = "SQS FIFO queue URL for reports"
  value       = aws_sqs_queue.reports.url
}

output "sqs_thread_ids_dlq_url" {
  description = "SQS FIFO DLQ URL for thread IDs"
  value       = aws_sqs_queue.thread_ids_dlq.url
}

output "sqs_reports_dlq_url" {
  description = "SQS FIFO DLQ URL for reports"
  value       = aws_sqs_queue.reports_dlq.url
}

output "rails_master_key_secret_arn" {
  description = "Secrets Manager ARN for RAILS_MASTER_KEY"
  value       = aws_secretsmanager_secret.rails_master_key.arn
}

output "redis_url_secret_arn" {
  description = "Secrets Manager ARN for REDIS_URL"
  value       = aws_secretsmanager_secret.redis_url.arn
}

output "google_client_id_secret_arn" {
  description = "Secrets Manager ARN for GOOGLE_CLIENT_ID"
  value       = aws_secretsmanager_secret.google_client_id.arn
}

output "google_client_secret_secret_arn" {
  description = "Secrets Manager ARN for GOOGLE_CLIENT_SECRET"
  value       = aws_secretsmanager_secret.google_client_secret.arn
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

output "acm_validation_records" {
  description = "DNS CNAME records required to validate the ACM certificate"
  value = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
}

output "thread_batch_worker_poll_interval" {
  description = "THREAD_BATCH_WORKER_POLL_INTERVAL"
  value       = tostring(var.thread_batch_worker_poll_interval)
}

output "thread_batch_worker_lock_ttl" {
  description = "THREAD_BATCH_WORKER_LOCK_TTL"
  value       = tostring(var.thread_batch_worker_lock_ttl)
}

output "thread_batch_worker_max_messages_per_run" {
  description = "THREAD_BATCH_WORKER_MAX_MESSAGES_PER_RUN"
  value       = tostring(var.thread_batch_worker_max_messages_per_run)
}

output "spreadsheet_sync_worker_poll_interval" {
  description = "SPREADSHEET_SYNC_WORKER_POLL_INTERVAL"
  value       = tostring(var.spreadsheet_sync_worker_poll_interval)
}

output "spreadsheet_sync_worker_lock_ttl" {
  description = "SPREADSHEET_SYNC_WORKER_LOCK_TTL"
  value       = tostring(var.spreadsheet_sync_worker_lock_ttl)
}

output "thread_list_worker_threads_per_message" {
  description = "THREAD_LIST_WORKER_THREADS_PER_MESSAGE"
  value       = tostring(var.thread_list_worker_threads_per_message)
}

output "thread_batch_fetcher_batch_size" {
  description = "THREAD_BATCH_FETCHER_BATCH_SIZE"
  value       = tostring(var.thread_batch_fetcher_batch_size)
}

output "thread_batch_fetcher_inter_batch_sleep" {
  description = "THREAD_BATCH_FETCHER_INTER_BATCH_SLEEP"
  value       = tostring(var.thread_batch_fetcher_inter_batch_sleep)
}

output "thread_list_worker_thread_id_limit" {
  description = "THREAD_LIST_WORKER_THREAD_ID_LIMIT"
  value       = tostring(var.thread_list_worker_thread_id_limit)
}

output "spreadsheet_sync_worker_max_messages_per_run" {
  description = "SPREADSHEET_SYNC_WORKER_MAX_MESSAGES_PER_RUN"
  value       = tostring(var.spreadsheet_sync_worker_max_messages_per_run)
}

output "sync_min_interval" {
  description = "SYNC_MIN_INTERVAL"
  value       = tostring(var.sync_min_interval)
}
