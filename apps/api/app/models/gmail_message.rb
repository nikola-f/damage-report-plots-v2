# frozen_string_literal: true

# Wraps a single Gmail message from the threads.get API response.
# Filters payload parts to only text/html, exposing body data for downstream processing.
class GmailMessage
  HTML_MIME_TYPE = "text/html"

  attr_reader :id, :internal_date

  def initialize(raw)
    @id            = raw["id"]
    @internal_date = raw["internalDate"]
    @html_parts    = (raw.dig("payload", "parts") || [])
                       .select { |p| p["mimeType"] == HTML_MIME_TYPE }
  end

  # @return [Array<String>] base64url-encoded data strings from text/html parts
  def html_body_data
    @html_parts.filter_map { |p| p.dig("body", "data") }
  end
end
