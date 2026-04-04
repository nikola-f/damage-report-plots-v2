# frozen_string_literal: true

# Immutable value object representing a Gmail search query.
# Converts structured search criteria into a Gmail query string.
#
# @example
#   query = GmailSearchQuery.new(
#     subject:    "damage report",
#     after_date: Date.new(2024, 1, 1),
#     from:       ["a@example.com", "b@example.com"],
#     smaller:    "10m"
#   )
#   query.to_s
#   # => "subject:damage report after:2024/01/01 {from:a@example.com from:b@example.com} smaller:10m"
GmailSearchQuery = Data.define(:subject, :after_date, :before_date, :from, :smaller) do
  def initialize(subject: nil, after_date: nil, before_date: nil, from: [], smaller: nil)
    super(subject:, after_date:, before_date:, from: Array(from), smaller:)
  end

  # @return [String, nil] Gmail query string, or nil if no criteria are set
  def to_s
    parts = []
    parts << "subject:#{subject}"                         if subject
    parts << "after:#{after_date.strftime("%Y/%m/%d")}"   if after_date
    parts << "before:#{before_date.strftime("%Y/%m/%d")}" if before_date
    parts << from_query                                    if from.any?
    parts << "smaller:#{smaller}"                         if smaller
    parts.empty? ? nil : parts.join(" ")
  end

  private

  def from_query
    return "from:#{from.first}" if from.one?

    "{#{from.map { |f| "from:#{f}" }.join(" ")}}"
  end
end
