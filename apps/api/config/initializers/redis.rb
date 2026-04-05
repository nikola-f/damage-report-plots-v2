# frozen_string_literal: true

REDIS = Redis.new(url: Settings.redis_url)
