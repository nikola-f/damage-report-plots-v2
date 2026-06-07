resource "aws_ssm_parameter" "thread_batch_worker_poll_interval" {
  name  = "/${local.name_prefix}/thread_batch_worker_poll_interval"
  type  = "String"
  value = tostring(var.thread_batch_worker_poll_interval)

  tags = {
    Name = "${local.name_prefix}-worker-poll-interval"
  }
}

resource "aws_ssm_parameter" "thread_batch_worker_lock_ttl" {
  name  = "/${local.name_prefix}/thread_batch_worker_lock_ttl"
  type  = "String"
  value = tostring(var.thread_batch_worker_lock_ttl)

  tags = {
    Name = "${local.name_prefix}-worker-lock-ttl"
  }
}

resource "aws_ssm_parameter" "thread_batch_worker_max_messages_per_run" {
  name  = "/${local.name_prefix}/thread_batch_worker_max_messages_per_run"
  type  = "String"
  value = tostring(var.thread_batch_worker_max_messages_per_run)

  tags = {
    Name = "${local.name_prefix}-worker-max-messages-per-run"
  }
}

resource "aws_ssm_parameter" "spreadsheet_sync_worker_poll_interval" {
  name  = "/${local.name_prefix}/spreadsheet_sync_worker_poll_interval"
  type  = "String"
  value = tostring(var.spreadsheet_sync_worker_poll_interval)

  tags = {
    Name = "${local.name_prefix}-spreadsheet-sync-worker-poll-interval"
  }
}

resource "aws_ssm_parameter" "spreadsheet_sync_worker_lock_ttl" {
  name  = "/${local.name_prefix}/spreadsheet_sync_worker_lock_ttl"
  type  = "String"
  value = tostring(var.spreadsheet_sync_worker_lock_ttl)

  tags = {
    Name = "${local.name_prefix}-spreadsheet-sync-worker-lock-ttl"
  }
}

resource "aws_ssm_parameter" "thread_batch_fetcher_batch_size" {
  name  = "/${local.name_prefix}/thread_batch_fetcher_batch_size"
  type  = "String"
  value = tostring(var.thread_batch_fetcher_batch_size)

  tags = {
    Name = "${local.name_prefix}-thread-batch-fetcher-batch-size"
  }
}

resource "aws_ssm_parameter" "thread_batch_fetcher_inter_batch_sleep" {
  name  = "/${local.name_prefix}/thread_batch_fetcher_inter_batch_sleep"
  type  = "String"
  value = tostring(var.thread_batch_fetcher_inter_batch_sleep)

  tags = {
    Name = "${local.name_prefix}-thread-batch-fetcher-inter-batch-sleep"
  }
}

resource "aws_ssm_parameter" "thread_list_worker_threads_per_message" {
  name  = "/${local.name_prefix}/thread_list_worker_threads_per_message"
  type  = "String"
  value = tostring(var.thread_list_worker_threads_per_message)

  tags = {
    Name = "${local.name_prefix}-thread-list-worker-threads-per-message"
  }
}

resource "aws_ssm_parameter" "thread_list_worker_thread_id_limit" {
  name  = "/${local.name_prefix}/thread_list_worker_thread_id_limit"
  type  = "String"
  value = tostring(var.thread_list_worker_thread_id_limit)

  tags = {
    Name = "${local.name_prefix}-thread-list-worker-thread-id-limit"
  }
}

resource "aws_ssm_parameter" "spreadsheet_sync_worker_max_messages_per_run" {
  name  = "/${local.name_prefix}/spreadsheet_sync_worker_max_messages_per_run"
  type  = "String"
  value = tostring(var.spreadsheet_sync_worker_max_messages_per_run)

  tags = {
    Name = "${local.name_prefix}-spreadsheet-sync-worker-max-messages-per-run"
  }
}
