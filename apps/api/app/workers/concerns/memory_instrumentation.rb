# frozen_string_literal: true

# Reads process memory from /proc/self/status so a worker can log how much RSS
# it consumes under real load. GmailThreadBatchWorker is serialized by a Redis
# lock and is the dominant memory consumer, so process RSS during its run
# approximates the worker's own footprint.
#
# Linux/Fargate only; returns nil where /proc/self/status is unavailable
# (e.g. a non-Linux dev machine) so callers can log the value safely.
module MemoryInstrumentation
  PROC_STATUS = "/proc/self/status"

  # Current resident set size in MB.
  def current_rss_mb = rss_mb_for("VmRSS")

  # Process lifetime peak RSS (high-water mark) in MB.
  def peak_rss_mb = rss_mb_for("VmHWM")

  private

  def rss_mb_for(field)
    return nil unless File.exist?(PROC_STATUS)

    line = File.foreach(PROC_STATUS).find { |l| l.start_with?("#{field}:") }
    line && (line.split[1].to_i / 1024.0).round(1) # kB -> MB
  end
end
