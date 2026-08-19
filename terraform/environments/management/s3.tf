resource "aws_s3_bucket_policy" "tfstate" {
  bucket = "drp-tfstate"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::drp-tfstate",
          "arn:aws:s3:::drp-tfstate/*",
        ]
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::${var.dev_account_id}:role/github-actions-terraform",
            "arn:aws:iam::${var.prod_account_id}:role/github-actions-terraform",
          ]
        }
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::drp-tfstate",
          "arn:aws:s3:::drp-tfstate/*",
        ]
      },
    ]
  })
}
