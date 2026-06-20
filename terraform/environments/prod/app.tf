module "app_infra" {
  source = "../../modules/app_infra"

  app_name                     = var.app_name
  environment                  = "prod"
  domain_name                  = var.api_domain_name
  rails_master_key_placeholder = var.rails_master_key_placeholder
  allowed_origins              = var.api_allowed_origins
  frontend_domain_name         = var.frontend_domain_name

  # Settings tuning values (per-environment; tune independently from dev)
  thread_batch_worker_poll_interval            = 30
  thread_batch_worker_lock_ttl                 = 900
  thread_batch_worker_max_messages_per_run     = 3
  spreadsheet_sync_worker_poll_interval        = 30
  spreadsheet_sync_worker_lock_ttl             = 300
  thread_list_worker_threads_per_message       = 500
  thread_batch_fetcher_batch_size              = 20
  thread_batch_fetcher_inter_batch_sleep       = 0.2
  thread_list_worker_thread_id_limit           = 10000
  spreadsheet_sync_worker_max_messages_per_run = 3
  sync_min_interval                            = 300

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
