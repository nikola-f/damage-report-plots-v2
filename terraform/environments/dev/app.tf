module "app_infra" {
  source = "../../modules/app_infra"

  app_name                     = var.app_name
  environment                  = "dev"
  domain_name                  = var.api_domain_name
  rails_master_key_placeholder = var.rails_master_key_placeholder
  allowed_origins              = var.api_allowed_origins
}
