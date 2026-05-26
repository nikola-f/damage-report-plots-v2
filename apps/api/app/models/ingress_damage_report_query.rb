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
  DEFAULT_AFTER_DATE = "2012-10-15"
  MONTHS_RANGE = 120

  def initialize(after_date: nil)
    @after = Date.parse(after_date || DEFAULT_AFTER_DATE)
  end

  def to_s
    GmailSearchQuery.new(
      subject: SUBJECT,
      after_date: @after,
      before_date: @after >> MONTHS_RANGE,
      from: FROM,
      larger: LARGER,
      smaller: SMALLER
    ).to_s
  end
end
