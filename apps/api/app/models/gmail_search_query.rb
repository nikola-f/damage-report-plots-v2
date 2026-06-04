# frozen_string_literal: true

# Immutable value object representing a Gmail search query.
# Converts structured search criteria into a Gmail query string.
#
# @example
#   query = GmailSearchQuery.new(
#     subject:    "damage report",
#     after_date: Date.new(2024, 1, 1),
#     from:       ["a@example.com", "b@example.com"],
#     larger:     "5K",
#     smaller:    "10m"
#   )
#   query.to_s
#   # => "subject:damage report after:2024/01/01 {from:a@example.com from:b@example.com} larger:5K smaller:10m"
GmailSearchQuery = Data.define(:subject, :after_date, :before_date, :from, :larger, :smaller) do
  # rubocop:disable Metrics/ParameterLists
  def initialize(subject: nil, after_date: nil, before_date: nil, from: [], larger: nil, smaller: nil)
    super(subject:, after_date:, before_date:, from: Array(from), larger:, smaller:)
  end
  # rubocop:enable Metrics/ParameterLists

  # @return [String, nil] Gmail query string, or nil if no criteria are set
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
  def to_s
    parts = []
    parts << "subject:#{subject}"                        if subject
    parts << "after:#{after_date}"   if after_date
    parts << "before:#{before_date}" if before_date
    parts << from_query                                   if from.any?
    parts << "larger:#{larger}"                          if larger
    parts << "smaller:#{smaller}"                        if smaller
    parts.empty? ? nil : parts.join(" ")
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

  private

  def from_query
    return "from:#{from.first}" if from.one?

    "{#{from.map { |f| "from:#{f}" }.join(" ")}}"
  end
end
