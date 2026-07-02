# frozen_string_literal: true

module PollingWorker
  # Compare-and-delete: release the lock only while it still holds this
  # worker's token. A run that outlives the TTL loses the lock to the next
  # worker; an unconditional DEL here would then delete that worker's lock
  # and let a third one in, breaking mutual exclusion.
  RELEASE_LOCK_SCRIPT = <<~LUA
    if redis.call("get", KEYS[1]) == ARGV[1] then
      return redis.call("del", KEYS[1])
    else
      return 0
    end
  LUA

  def with_lock(key:, ttl:, interval:)
    token    = SecureRandom.uuid
    acquired = REDIS.set(key, token, nx: true, ex: ttl)

    unless acquired
      logger.debug "another #{self.class.name} is running, skipping"
      self.class.perform_in(interval)
      return
    end

    begin
      yield
    ensure
      REDIS.eval(RELEASE_LOCK_SCRIPT, keys: [key], argv: [token])
      self.class.perform_in(interval)
    end
  end
end
