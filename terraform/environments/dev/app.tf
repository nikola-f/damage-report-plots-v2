module "app_infra" {
  source = "../../modules/app_infra"

  app_name             = var.app_name
  environment          = "dev"
  frontend_domain_name = var.frontend_domain_name

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
