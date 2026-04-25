# frozen_string_literal: true

# Immutable value object representing a damage report processing task.
# Serialized to JSON and queued to SQS for downstream processing.
#
# @example
#   task = ReportTask.new(thread_id: "abc123")
#   task.to_h  # => { thread_id: "abc123" }
ReportTask = Data.define(:thread_id)
