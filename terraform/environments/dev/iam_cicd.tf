resource "aws_iam_role" "github_actions_terraform" {
  name = "github-actions-terraform"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.management_account_id}:role/github-actions-terraform"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# No policy attached yet — add least-privilege policies as AWS resources are provisioned in this environment
