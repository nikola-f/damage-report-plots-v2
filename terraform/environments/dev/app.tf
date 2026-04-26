module "app_infra" {
  source = "../../modules/app_infra"

  app_name                        = var.app_name
  environment                     = "dev"
  domain_name                     = var.domain_name
  elasticache_replication_enabled = false
  rails_master_key_placeholder    = var.rails_master_key_placeholder
  allowed_origins                 = var.allowed_origins
}
