data "aws_caller_identity" "current" {}

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
        Action = ["sts:AssumeRole", "sts:TagSession"]
      }
    ]
  })
}

resource "aws_iam_role_policy" "iam_read" {
  name = "iam-read"
  role = aws_iam_role.github_actions_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/github-actions-terraform"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:ListPolicyTags",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/cloudfront-frontend"
      }
    ]
  })
}

# Permissions the CI role needs to manage the remaining infrastructure: the
# frontend (ACM + S3 + CloudFront) and the account CloudTrail. The backend
# pipeline's permissions (EC2/VPC, ECS, ECR, ELB, ElastiCache, SQS, Secrets,
# SSM, WAF, Firehose, log groups/subscriptions, autoscaling, service-linked
# roles, and the drp-* task-role IAM) were removed with the backend in
# Phase 3 (Stages 1-5).
resource "aws_iam_role_policy" "terraform_app_infra" {
  name = "terraform-app-infra"
  role = aws_iam_role.github_actions_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "acm:RequestCertificate", "acm:DeleteCertificate", "acm:DescribeCertificate",
          "acm:ListCertificates", "acm:AddTagsToCertificate", "acm:ListTagsForCertificate",
          "acm:RenewCertificate",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:CreateBucket", "s3:DeleteBucket",
          "s3:Get*", "s3:List*",
          "s3:PutBucketAcl",
          "s3:PutBucketPolicy", "s3:DeleteBucketPolicy",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutLifecycleConfiguration",
          "s3:PutBucketTagging",
          "s3:PutEncryptionConfiguration",
          "s3:PutObject", "s3:DeleteObject",
          "s3:PutBucketCORS",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudtrail:DescribeTrails",
          "cloudtrail:GetTrail",
          "cloudtrail:GetTrailStatus",
          "cloudtrail:ListTrails",
          "cloudtrail:ListTags",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudtrail:CreateTrail",
          "cloudtrail:DeleteTrail",
          "cloudtrail:UpdateTrail",
          "cloudtrail:StartLogging",
          "cloudtrail:StopLogging",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:GetEventSelectors",
          "cloudtrail:AddTags",
          "cloudtrail:RemoveTags",
        ]
        Resource = "arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/drp-*"
      },
    ]
  })
}

# Customer managed policy (not inline): the role's inline policies hit the
# 10,240-byte total limit. Managed policies do not count toward it.
resource "aws_iam_policy" "cloudfront_frontend" {
  name = "cloudfront-frontend"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudfront:CreateDistribution", "cloudfront:DeleteDistribution",
          "cloudfront:GetDistribution", "cloudfront:GetDistributionConfig",
          "cloudfront:UpdateDistribution", "cloudfront:ListDistributions",
          "cloudfront:CreateOriginAccessControl", "cloudfront:DeleteOriginAccessControl",
          "cloudfront:GetOriginAccessControl", "cloudfront:GetOriginAccessControlConfig",
          "cloudfront:UpdateOriginAccessControl", "cloudfront:ListOriginAccessControls",
          "cloudfront:TagResource", "cloudfront:UntagResource", "cloudfront:ListTagsForResource",
          "cloudfront:CreateInvalidation", "cloudfront:GetInvalidation",
          "cloudfront:CreateResponseHeadersPolicy", "cloudfront:DeleteResponseHeadersPolicy",
          "cloudfront:GetResponseHeadersPolicy", "cloudfront:GetResponseHeadersPolicyConfig",
          "cloudfront:UpdateResponseHeadersPolicy", "cloudfront:ListResponseHeadersPolicies",
          "cloudfront:CreateFunction", "cloudfront:DeleteFunction",
          "cloudfront:DescribeFunction", "cloudfront:GetFunction",
          "cloudfront:PublishFunction", "cloudfront:UpdateFunction", "cloudfront:ListFunctions",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudfront_frontend" {
  role       = aws_iam_role.github_actions_terraform.name
  policy_arn = aws_iam_policy.cloudfront_frontend.arn
}

resource "aws_iam_role_policy" "tfstate_read" {
  name = "tfstate-read"
  role = aws_iam_role.github_actions_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::drp-tfstate/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::drp-tfstate"
      },
    ]
  })
}
