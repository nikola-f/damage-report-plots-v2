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

resource "aws_ssm_parameter" "thread_list_worker_threads_per_message" {
  name  = "/${local.name_prefix}/thread_list_worker_threads_per_message"
  type  = "String"
  value = tostring(var.thread_list_worker_threads_per_message)

  tags = {
    Name = "${local.name_prefix}-thread-list-worker-threads-per-message"
  }
}
