# frozen_string_literal: true

# Represents a single portal entry extracted from an Ingress damage report email.
DamageReportRecord = Data.define(:name, :latitude, :longitude, :owned, :internal_date)
