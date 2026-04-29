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

data "aws_organizations_organization" "main" {}

resource "aws_guardduty_member" "dev" {
  detector_id = aws_guardduty_detector.main.id
  account_id  = var.dev_account_id
  email       = one([for a in data.aws_organizations_organization.main.accounts : a.email if a.id == var.dev_account_id])

  depends_on = [aws_guardduty_organization_admin_account.main]
}

resource "aws_guardduty_member" "prod" {
  detector_id = aws_guardduty_detector.main.id
  account_id  = var.prod_account_id
  email       = one([for a in data.aws_organizations_organization.main.accounts : a.email if a.id == var.prod_account_id])

  depends_on = [aws_guardduty_organization_admin_account.main]
}
