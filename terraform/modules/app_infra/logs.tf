# ---------- S3: general logs (ALB + containers + Redis) ----------

resource "aws_s3_bucket" "logs" {
  bucket = "drp-${var.environment}-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${local.name_prefix}-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-180-days"
    status = "Enabled"

    filter {}

    expiration {
      days = 180
    }
  }
}

data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.main.arn }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      },
      {
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.logs.arn
      },
    ]
  })
}

# ---------- S3: WAF logs (bucket name must start with aws-waf-logs-) ----------

resource "aws_s3_bucket" "waf_logs" {
  bucket = "aws-waf-logs-drp-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${local.name_prefix}-waf-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  rule {
    id     = "expire-180-days"
    status = "Enabled"

    filter {}

    expiration {
      days = 180
    }
  }
}

resource "aws_s3_bucket_policy" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.waf_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"    = "bucket-owner-full-control"
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.waf_logs.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      },
    ]
  })
}

# ---------- IAM: Firehose role (writes to S3) ----------

resource "aws_iam_role" "firehose" {
  name = "${local.name_prefix}-firehose"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "firehose" {
  name = "s3-delivery"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject",
      ]
      Resource = [
        aws_s3_bucket.logs.arn,
        "${aws_s3_bucket.logs.arn}/*",
      ]
    }]
  })
}

# ---------- IAM: CloudWatch Logs role (puts records to Firehose) ----------

resource "aws_iam_role" "cwlogs_firehose" {
  name = "${local.name_prefix}-cwlogs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "logs.${var.aws_region}.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringLike = {
          "aws:SourceArn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "cwlogs_firehose" {
  name = "firehose-put"
  role = aws_iam_role.cwlogs_firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["firehose:PutRecord", "firehose:PutRecordBatch"]
      Resource = [
        aws_kinesis_firehose_delivery_stream.web.arn,
        aws_kinesis_firehose_delivery_stream.worker.arn,
        aws_kinesis_firehose_delivery_stream.redis.arn,
      ]
    }]
  })
}

# ---------- Kinesis Firehose streams ----------

resource "aws_kinesis_firehose_delivery_stream" "web" {
  name        = "${local.name_prefix}-firehose-web"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.logs.arn
    prefix     = "containers/web/"
  }
}

resource "aws_kinesis_firehose_delivery_stream" "worker" {
  name        = "${local.name_prefix}-firehose-worker"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.logs.arn
    prefix     = "containers/worker/"
  }
}

resource "aws_kinesis_firehose_delivery_stream" "redis" {
  name        = "${local.name_prefix}-firehose-redis"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.logs.arn
    prefix     = "redis/"
  }
}

# ---------- CloudWatch Logs subscription filters ----------

resource "aws_cloudwatch_log_subscription_filter" "web" {
  name            = "${local.name_prefix}-web-to-firehose"
  log_group_name  = aws_cloudwatch_log_group.web.name
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.web.arn
  role_arn        = aws_iam_role.cwlogs_firehose.arn
}

resource "aws_cloudwatch_log_subscription_filter" "worker" {
  name            = "${local.name_prefix}-worker-to-firehose"
  log_group_name  = aws_cloudwatch_log_group.worker.name
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.worker.arn
  role_arn        = aws_iam_role.cwlogs_firehose.arn
}

resource "aws_cloudwatch_log_subscription_filter" "redis" {
  name            = "${local.name_prefix}-redis-to-firehose"
  log_group_name  = aws_cloudwatch_log_group.redis_slow_log.name
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.redis.arn
  role_arn        = aws_iam_role.cwlogs_firehose.arn
}
