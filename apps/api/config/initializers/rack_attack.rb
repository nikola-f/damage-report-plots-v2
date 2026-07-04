# frozen_string_literal: true

# Per-client-IP rate limiting. Replaces the WAF RateLimitGlobal rule, which
# aggregated by CloudFront edge IP (the ALB's connection source) and therefore
# never counted per user.
class Rack::Attack
  class Request < ::Rack::Request
    # Behind CloudFront → ALB, X-Forwarded-For arrives as
    #   "<client-supplied...>, <viewer IP>, <edge IP>"
    # CloudFront appends the viewer IP and ALB appends the CloudFront edge IP,
    # so only the last two entries are trustworthy; anything earlier is
    # client-supplied and spoofable. Key on the second-to-last entry. Without
    # a proxy chain (local/dev/test) fall back to the connection IP.
    def client_ip
      forwarded = (get_header("HTTP_X_FORWARDED_FOR") || "").split(",").map(&:strip)
      forwarded[-2] || ip
    end
  end

  # Mirrors the removed WAF rule. /up is excluded: ALB health checks share the
  # ALB's own IPs and would otherwise consume (and eventually trip) one bucket.
  throttle("global/ip", limit: Settings.rate_limit_global_limit, period: Settings.rate_limit_global_period) do |req|
    req.client_ip unless req.path == "/up"
  end

  # Tighter limit for the OAuth surface (login, callback, scope grants) —
  # unauthenticated and therefore the main abuse target.
  throttle("auth/ip", limit: Settings.rate_limit_auth_limit, period: Settings.rate_limit_auth_period) do |req|
    req.client_ip if req.path.start_with?("/auth/")
  end

  # 429, not the default 403: CloudFront's custom_error_response rewrites
  # 403/404 into the SPA's index.html (200), which would mask throttling.
  self.throttled_responder = lambda do |request|
    match_data  = request.env["rack.attack.match_data"]
    retry_after = match_data[:period] - (match_data[:epoch_time] % match_data[:period])
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [{ error: "rate_limited" }.to_json]
    ]
  end
end

if Rails.env.test?
  # Hermetic: no Redis dependency, and disabled so throttle counters don't
  # leak into unrelated request specs. rate_limit_spec enables it per example.
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  Rack::Attack.enabled = false
else
  # Own connection rather than the shared REDIS constant: initializers load
  # alphabetically, so redis.rb hasn't run yet, and a dedicated connection
  # keeps throttle counters off the UserStore/session hot path anyway.
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(redis: Redis.new(url: Settings.redis_url))
end
