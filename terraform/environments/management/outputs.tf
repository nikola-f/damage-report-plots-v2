output "github_actions_role_arn" {
  description = "Set this as AWS_OIDC_ROLE_ARN in GitHub Environments (dev and prod)"
  value       = aws_iam_role.github_actions_terraform.arn
}
