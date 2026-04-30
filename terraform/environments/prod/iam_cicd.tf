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
      }
    ]
  })
}

resource "aws_iam_role_policy" "terraform_app_infra" {
  name = "terraform-app-infra"
  role = aws_iam_role.github_actions_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:DescribeVpcs", "ec2:ModifyVpcAttribute",
          "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:DescribeSubnets", "ec2:ModifySubnetAttribute",
          "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:DescribeInternetGateways",
          "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
          "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:AssociateAddress", "ec2:DisassociateAddress",
          "ec2:DescribeAddresses", "ec2:DescribeAddressesAttribute",
          "ec2:CreateNatGateway", "ec2:DeleteNatGateway", "ec2:DescribeNatGateways",
          "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:DescribeRouteTables",
          "ec2:CreateRoute", "ec2:DeleteRoute",
          "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:DescribeSecurityGroups",
          "ec2:DescribeSecurityGroupRules",
          "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
          "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
          "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
          "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeTags",
          "ec2:DescribeAvailabilityZones", "ec2:DescribeAccountAttributes",
          "ec2:DescribeNetworkInterfaces", "ec2:DescribePrefixLists",
          "ec2:DescribeVpcAttribute", "ec2:DescribeSubnetAttribute",
          "ec2:GetSecurityGroupsForVpc",
        ]
        Resource = "*"
      },
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
          "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy", "logs:ListTagsLogGroup", "logs:TagLogGroup", "logs:UntagLogGroup",
          "logs:ListTagsForResource", "logs:TagResource", "logs:UntagResource",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:DescribeRepositories",
          "ecr:PutLifecyclePolicy", "ecr:GetLifecyclePolicy", "ecr:DeleteLifecyclePolicy",
          "ecr:PutImageScanningConfiguration", "ecr:PutImageTagMutability",
          "ecr:GetRepositoryPolicy", "ecr:SetRepositoryPolicy", "ecr:DeleteRepositoryPolicy",
          "ecr:ListTagsForResource", "ecr:TagResource", "ecr:UntagResource",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:CreateCluster", "ecs:DeleteCluster", "ecs:DescribeClusters",
          "ecs:UpdateClusterSettings", "ecs:PutClusterCapacityProviders",
          "ecs:ListClusters", "ecs:ListTagsForResource", "ecs:TagResource", "ecs:UntagResource",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:CreateServiceLinkedRole"
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = [
              "elasticloadbalancing.amazonaws.com",
              "elasticache.amazonaws.com",
              "ecs.amazonaws.com",
              "wafv2.amazonaws.com",
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole",
          "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:TagRole", "iam:UntagRole", "iam:ListInstanceProfilesForRole", "iam:PassRole",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/drp-*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:ModifyLoadBalancerAttributes", "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets", "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:CreateTargetGroup", "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:ModifyTargetGroup", "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DescribeListeners", "elasticloadbalancing:DescribeListenerAttributes",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:CreateRule", "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:DescribeRules", "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:AddTags", "elasticloadbalancing:DescribeTags", "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:SetWebACL",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticache:CreateCacheSubnetGroup", "elasticache:DeleteCacheSubnetGroup",
          "elasticache:DescribeCacheSubnetGroups",
          "elasticache:CreateCacheCluster", "elasticache:DeleteCacheCluster",
          "elasticache:DescribeCacheClusters", "elasticache:ModifyCacheCluster",
          "elasticache:CreateReplicationGroup", "elasticache:DeleteReplicationGroup",
          "elasticache:DescribeReplicationGroups", "elasticache:ModifyReplicationGroup",
          "elasticache:AddTagsToResource", "elasticache:ListTagsForResource", "elasticache:RemoveTagsFromResource",
          "elasticache:DescribeCacheEngineVersions", "elasticache:DescribeCacheParameterGroups",
          "elasticache:DescribeCacheParameters",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:CreateQueue", "sqs:DeleteQueue", "sqs:GetQueueAttributes", "sqs:SetQueueAttributes",
          "sqs:GetQueueUrl", "sqs:TagQueue", "sqs:UntagQueue", "sqs:ListQueueTags", "sqs:ListQueues",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret", "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue", "secretsmanager:UpdateSecret",
          "secretsmanager:GetResourcePolicy", "secretsmanager:PutResourcePolicy", "secretsmanager:DeleteResourcePolicy",
          "secretsmanager:TagResource", "secretsmanager:UntagResource", "secretsmanager:ListSecretVersionIds",
          "secretsmanager:RestoreSecret",
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
          "firehose:CreateDeliveryStream", "firehose:DeleteDeliveryStream",
          "firehose:DescribeDeliveryStream", "firehose:ListDeliveryStreams",
          "firehose:TagDeliveryStream", "firehose:UntagDeliveryStream",
          "firehose:ListTagsForDeliveryStream", "firehose:UpdateDestination",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutSubscriptionFilter", "logs:DeleteSubscriptionFilter",
          "logs:DescribeSubscriptionFilters",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "application-autoscaling:DescribeScalableTargets",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudtrail:CreateTrail",
          "cloudtrail:DeleteTrail",
          "cloudtrail:DescribeTrails",
          "cloudtrail:GetTrail",
          "cloudtrail:GetTrailStatus",
          "cloudtrail:UpdateTrail",
          "cloudtrail:StartLogging",
          "cloudtrail:StopLogging",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:GetEventSelectors",
          "cloudtrail:AddTags",
          "cloudtrail:RemoveTags",
          "cloudtrail:ListTags",
        ]
        Resource = "arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/drp-*"
      },
      {
        Effect = "Allow"
        Action = [
          "wafv2:CreateWebACL", "wafv2:DeleteWebACL", "wafv2:GetWebACL", "wafv2:UpdateWebACL",
          "wafv2:ListWebACLs",
          "wafv2:AssociateWebACL", "wafv2:DisassociateWebACL",
          "wafv2:GetWebACLForResource", "wafv2:ListResourcesForWebACL",
          "wafv2:ListTagsForResource", "wafv2:TagResource", "wafv2:UntagResource",
          "wafv2:CheckCapacity", "wafv2:DescribeManagedRuleGroup",
          "wafv2:PutLoggingConfiguration", "wafv2:GetLoggingConfiguration", "wafv2:DeleteLoggingConfiguration",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "ecr_ecs_deploy" {
  name = "ecr-ecs-deploy"
  role = aws_iam_role.github_actions_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
        ]
        Resource = module.app_infra.ecr_repository_arn
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:CreateService",
          "ecs:DeleteService",
          "ecs:DescribeServices",
          "ecs:UpdateService",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:ListServiceDeployments",
          "ecs:TagResource",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          module.app_infra.task_execution_role_arn,
          module.app_infra.task_role_arn,
        ]
      },
    ]
  })
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
