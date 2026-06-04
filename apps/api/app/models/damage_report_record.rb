# frozen_string_literal: true

require "digest"

# Represents a single portal entry extracted from an Ingress damage report email.
DamageReportRecord = Data.define(:name, :latitude, :longitude, :owned, :internal_date) do
  # Printable ASCII excluding " (breaks CSV) and ' (Sheets text prefix).
  # Larger alphabet → shorter Sqids IDs.
  SQIDS_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!#$%&()*+,-./:;<=>?@[]^_`{|}~"
  SQIDS          = Sqids.new(alphabet: SQIDS_ALPHABET)

  def self.from_h(hash)
    new(**hash.transform_keys(&:to_sym))
  end

  # Deduplicates records by name/latitude/longitude/internal_date.
  # When duplicates exist, owned:true survives over owned:false.
  def self.deduplicate(records)
    records
      .group_by { |r| [r.name, r.latitude, r.longitude, r.internal_date] }
      .values
      .map { |group| group.max_by { |r| r.owned ? 1 : 0 } }
  end

  def portal_id
    hash   = Digest::SHA256.digest("#{latitude},#{longitude}")
    number = hash.unpack1("Q>") & ((1 << 62) - 1) # Sqids max: 2^62 - 1
    SQIDS.encode([number])
  end
end
