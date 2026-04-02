# frozen_string_literal: true

# Immutable value object representing a damage report processing task.
# Serialized to JSON and queued to SQS for downstream processing.
#
# @example
#   task = ReportTask.new(
#     thread_id: "abc123",
#     user_id:   "user_001",
#     email:     "user@example.com"
#   )
#   task.to_h  # => { thread_id: "abc123", user_id: "user_001", email: "user@example.com" }
ReportTask = Data.define(:thread_id, :user_id, :email)
