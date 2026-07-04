# frozen_string_literal: true

class GmailThreadBatchWorker
  include Sidekiq::Worker
  include PollingWorker
  include MemoryInstrumentation

  sidekiq_options retry: 0

  LOCK_KEY = "gmail_thread_batch_worker:lock"

  def perform
    with_lock(key: LOCK_KEY, ttl: Settings.thread_batch_worker_lock_ttl, interval: Settings.thread_batch_worker_poll_interval) do
      portal_sqs = SqsClient.new(Settings.sqs_reports_queue_url)
      thread_sqs = SqsClient.new(Settings.sqs_thread_ids_queue_url)

      processed = 0
      loop do
        break if processed >= Settings.thread_batch_worker_max_messages_per_run

        messages = thread_sqs.receive_messages(
          message_attribute_names: [UserStore::USER_ID_ATTR],
          max_messages: 1
        )
        break if messages.empty?

        process_message(messages.first, thread_sqs:, portal_sqs:)
        processed += 1
      end
    end
  end

  private

  def process_message(message, thread_sqs:, portal_sqs:)
    user_id    = message.message_attributes[UserStore::USER_ID_ATTR].string_value
    thread_ids = JSON.parse(message.body)
    logger.info "sqs_message_id=#{message.message_id} threads=#{thread_ids.size} user=#{user_id}"

    portals, max_date = extract_portals(user_id, thread_ids)
    enqueue_portals(user_id, portals, portal_sqs)
    advance_resume_point(user_id, max_date)

    thread_sqs.delete_messages(message.receipt_handle)
    logger.debug "deleted thread_ids message for user #{user_id}"

    processed_total = UserStore.threads_processed.increment(user_id, by: thread_ids.size)
    record_completion(user_id, processed_total)
  end

  # Fetches the threads and extracts damage-report portals, logging timing and
  # memory instrumentation. Returns the portals and the max internalDate seen.
  def extract_portals(user_id, thread_ids)
    access_token = UserStore.access_token.fetch(user_id)

    t_start      = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    extract_ms   = 0
    portals      = []
    max_date     = 0
    rss_base     = current_rss_mb
    alloc_base   = GC.stat(:total_allocated_objects)
    gc_base      = GC.count
    rss_peak     = rss_base
    GmailThreadBatchFetcher.new(access_token:).call(thread_ids) do |gmail_message|
      t_ex = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      portals.concat(gmail_message.html_decoder&.extract_portals(internal_date: gmail_message.internal_date) || [])
      extract_ms += ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_ex) * 1000).round
      date = gmail_message.internal_date.to_i
      max_date = date if date > max_date
      rss_peak = [rss_peak, current_rss_mb].compact.max
    end
    fetch_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_start) * 1000).round - extract_ms
    logger.info "user=#{user_id} threads=#{thread_ids.size} fetch=#{fetch_ms}ms extract=#{extract_ms}ms portals=#{portals.size}"
    alloc_objs = GC.stat(:total_allocated_objects) - alloc_base
    logger.debug "user=#{user_id} threads=#{thread_ids.size} rss_base=#{rss_base}MB rss_peak=#{rss_peak}MB rss_now=#{current_rss_mb}MB alloc_objs=#{alloc_objs} gc_runs=#{GC.count - gc_base} vmhwm=#{peak_rss_mb}MB"

    [portals, max_date]
  end

  def enqueue_portals(user_id, portals, portal_sqs)
    unique_portals = DamageReportRecord.deduplicate(portals)
    return if unique_portals.empty?

    t_sqs = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    portal_sqs.send_messages(unique_portals.map(&:to_h),
                             attributes: { UserStore::USER_ID_ATTR => user_id })
    sqs_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_sqs) * 1000).round
    logger.info "user=#{user_id} sqs_send unique_portals=#{unique_portals.size} sqs=#{sqs_ms}ms"
    UserStore.portals_found.increment(user_id, by: unique_portals.size)
  end

  # The resume point is forward-only so out-of-order messages cannot move it
  # backwards.
  def advance_resume_point(user_id, max_date)
    current_max = UserStore.threads_max_internal_date.fetch_or_nil(user_id).to_i
    UserStore.threads_max_internal_date.store(user_id, max_date.to_s) if max_date > current_max
  end

  # Record last_processed_at once, when this sync run's batch stage finishes
  # (all discovered threads processed). Stamping per message would make the
  # timestamp climb throughout the drain; because a 429-rejected re-sync happens
  # while the previous run is still draining, that climb would surface in the
  # status endpoint as if the rejected sync had advanced "Sync finished". The
  # forward-only guard tolerates clock skew and repeated completion stamps.
  def record_completion(user_id, processed_total)
    found = UserStore.threads_found.fetch_or_nil(user_id).to_i
    return unless found.positive? && processed_total >= found

    now = Time.now.to_i
    last_processed = UserStore.last_processed_at.fetch_or_nil(user_id).to_i
    UserStore.last_processed_at.store(user_id, now.to_s) if last_processed < now
  end
end
