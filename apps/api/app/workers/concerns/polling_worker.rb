# frozen_string_literal: true

module PollingWorker
  def with_lock(key:, ttl:, interval:)
    acquired = REDIS.set(key, "1", nx: true, ex: ttl)

    unless acquired
      logger.debug "another #{self.class.name} is running, skipping"
      self.class.perform_in(interval)
      return
    end

    begin
      yield
    ensure
      REDIS.del(key)
      self.class.perform_in(interval)
    end
  end
end
