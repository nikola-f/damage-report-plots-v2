data "aws_organizations_organization" "main" {}

data "aws_organizations_organizational_units" "root" {
  parent_id = data.aws_organizations_organization.main.roots[0].id
}

locals {
  workloads_ou_id = one([
    for ou in data.aws_organizations_organizational_units.root.children : ou.id
    if ou.name == "workloads"
  ])
}

resource "aws_organizations_policy" "security_guardrails" {
  name        = "security-guardrails"
  description = "Prevent disabling CloudTrail and GuardDuty in member accounts"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyCloudTrailDisable"
        Effect = "Deny"
        Action = [
          "cloudtrail:StopLogging",
          "cloudtrail:DeleteTrail",
        ]
        Resource = "*"
        Condition = {
          ArnNotLike = {
            "aws:PrincipalARN" = "arn:aws:iam::*:role/github-actions-terraform"
          }
        }
      },
      {
        Sid    = "DenyGuardDutyDisable"
        Effect = "Deny"
        Action = [
          "guardduty:DeleteDetector",
          "guardduty:DisassociateFromAdministratorAccount",
        ]
        Resource = "*"
        Condition = {
          ArnNotLike = {
            "aws:PrincipalARN" = "arn:aws:iam::*:role/github-actions-terraform"
          }
        }
      },
    ]
  })
}

resource "aws_organizations_policy_attachment" "security_guardrails" {
  policy_id = aws_organizations_policy.security_guardrails.id
  target_id = local.workloads_ou_id
}
