# frozen_string_literal: true

# Builds a Gmail search query string for Ingress Damage Report emails.
#
# @example
#   query = DamageReportQuery.new(after_date: Time.utc(2024, 1, 1).to_i)
#   query.to_s
#   # => "subject:Ingress Damage Report: Entities attacked by after:1704067200 ..."
class DamageReportQuery
  SUBJECT = "Ingress Damage Report: Entities attacked by"
  FROM    = ["ingress-support@google.com",
             "ingress-support@nianticlabs.com",
             "ingress-support@nianticspatial.com"].freeze
  LARGER  = "5K"
  SMALLER = "100K"
  DEFAULT_AFTER_DATE = Time.utc(2012, 10, 15).to_i
  MONTHS_RANGE = 36

  def initialize(after_date: nil)
    @after = Time.at(after_date || DEFAULT_AFTER_DATE).utc.to_date
  end

  def to_s
    after_epoch  = date_to_epoch(@after)
    before_epoch = date_to_epoch(@after >> MONTHS_RANGE)
    from_part    = "{#{FROM.map { |f| "from:#{f}" }.join(" ")}}"
    "subject:#{SUBJECT} after:#{after_epoch} before:#{before_epoch} #{from_part} larger:#{LARGER} smaller:#{SMALLER}"
  end

  private

  def date_to_epoch(date)
    Time.utc(date.year, date.month, date.day).to_i
  end
end
