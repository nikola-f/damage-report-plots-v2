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

output "private_subnet_ids_csv" {
  description = "Private subnet IDs as a comma-separated string (for ecspresso jsonnet std.split)"
  value       = join(",", aws_subnet.private[*].id)
}

output "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs_tasks.id
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.api.repository_url
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
  description = "THREAD_BATCH_WORKER_POLL_INTERVAL value from SSM"
  value       = aws_ssm_parameter.thread_batch_worker_poll_interval.value
}

output "thread_batch_worker_lock_ttl" {
  description = "THREAD_BATCH_WORKER_LOCK_TTL value from SSM"
  value       = aws_ssm_parameter.thread_batch_worker_lock_ttl.value
}

output "thread_batch_worker_max_messages_per_run" {
  description = "THREAD_BATCH_WORKER_MAX_MESSAGES_PER_RUN value from SSM"
  value       = aws_ssm_parameter.thread_batch_worker_max_messages_per_run.value
}
