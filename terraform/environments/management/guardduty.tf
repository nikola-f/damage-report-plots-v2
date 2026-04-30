resource "aws_guardduty_detector" "main" {
  enable = true
}

resource "aws_guardduty_organization_admin_account" "main" {
  admin_account_id = data.aws_caller_identity.current.account_id
}

resource "aws_guardduty_organization_configuration" "main" {
  auto_enable_organization_members = "ALL"
  detector_id                      = aws_guardduty_detector.main.id

  depends_on = [aws_guardduty_organization_admin_account.main]
}
