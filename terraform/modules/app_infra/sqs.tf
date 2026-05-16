# ── DLQ ──────────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "thread_ids_dlq" {
  name                        = "${local.name_prefix}-thread-ids-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 1209600 # 14 days
  sqs_managed_sse_enabled     = true

  tags = {
    Name = "${local.name_prefix}-thread-ids-dlq"
  }
}

resource "aws_sqs_queue" "reports_dlq" {
  name                        = "${local.name_prefix}-reports-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 1209600 # 14 days
  sqs_managed_sse_enabled     = true

  tags = {
    Name = "${local.name_prefix}-reports-dlq"
  }
}

resource "aws_sqs_queue_redrive_allow_policy" "thread_ids_dlq" {
  queue_url = aws_sqs_queue.thread_ids_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.thread_ids.arn]
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "reports_dlq" {
  queue_url = aws_sqs_queue.reports_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.reports.arn]
  })
}

# ── メインキュー ──────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "thread_ids" {
  name                        = "${local.name_prefix}-thread-ids.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 60
  sqs_managed_sse_enabled     = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.thread_ids_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "${local.name_prefix}-thread-ids"
  }
}

resource "aws_sqs_queue" "reports" {
  name                        = "${local.name_prefix}-reports.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 60
  sqs_managed_sse_enabled     = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.reports_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "${local.name_prefix}-reports"
  }
}
