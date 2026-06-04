# frozen_string_literal: true

# Builds a GmailSearchQuery for Ingress Damage Report emails.
# Encapsulates all Ingress-specific search criteria in one place.
#
# @example
#   query = IngressDamageReportQuery.new(after_date: "2024-01-01")
#   query.to_s
#   # => "subject:Ingress Damage Report: Entities attacked by after:2024/01/01 ..."
class IngressDamageReportQuery
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
    GmailSearchQuery.new(
      subject:     SUBJECT,
      after_date:  date_to_epoch(@after),
      before_date: date_to_epoch(@after >> MONTHS_RANGE),
      from:        FROM,
      larger:      LARGER,
      smaller:     SMALLER
    ).to_s
  end

  private

  def date_to_epoch(date)
    Time.utc(date.year, date.month, date.day).to_i
  end
end
