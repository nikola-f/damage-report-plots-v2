resource "aws_sqs_queue" "thread_ids" {
  name                        = "${local.name_prefix}-thread-ids.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 60

  tags = {
    Name = "${local.name_prefix}-thread-ids"
  }
}

resource "aws_sqs_queue" "reports" {
  name                        = "${local.name_prefix}-reports.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 60

  tags = {
    Name = "${local.name_prefix}-reports"
  }
}
