data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # Thumbprints for token.actions.githubusercontent.com
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

resource "aws_iam_role" "github_actions_terraform" {
  name = "github-actions-terraform"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_org}/${var.github_repo}:environment:dev",
              "repo:${var.github_org}/${var.github_repo}:environment:prod",
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "terraform_state_access" {
  name = "terraform-state-access"
  role = aws_iam_role.github_actions_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
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
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
        ]
        Resource = "arn:aws:dynamodb:us-west-2:${data.aws_caller_identity.current.account_id}:table/drp-tfstate-lock"
      },
    ]
  })
}

resource "aws_iam_role_policy" "assume_terraform_roles" {
  name = "assume-terraform-roles"
  role = aws_iam_role.github_actions_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Resource = [
          "arn:aws:iam::${var.dev_account_id}:role/github-actions-terraform",
          "arn:aws:iam::${var.prod_account_id}:role/github-actions-terraform",
        ]
      }
    ]
  })
}
