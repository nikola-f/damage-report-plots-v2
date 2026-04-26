module "app_infra" {
  source = "../../modules/app_infra"

  app_name                        = var.app_name
  environment                     = "prod"
  domain_name                     = var.domain_name
  elasticache_replication_enabled = true
  rails_master_key_placeholder    = var.rails_master_key_placeholder
  allowed_origins                 = var.allowed_origins
}
