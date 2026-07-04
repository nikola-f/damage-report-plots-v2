# frozen_string_literal: true

# Google account IDs are quasi-identifiers; log lines keep only a short
# prefix — enough to correlate lines within the logs without recording the
# full ID.
module UserIdMasking
  VISIBLE_CHARS = 4

  def masked_user_id(user_id)
    "#{user_id.to_s[0, VISIBLE_CHARS]}***"
  end
end
