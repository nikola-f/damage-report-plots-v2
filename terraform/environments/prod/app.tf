module "app_infra" {
  source = "../../modules/app_infra"

  app_name                     = var.app_name
  environment                  = "prod"
  domain_name                  = var.api_domain_name
  rails_master_key_placeholder = var.rails_master_key_placeholder
  allowed_origins              = var.api_allowed_origins
  frontend_domain_name         = var.frontend_domain_name

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
