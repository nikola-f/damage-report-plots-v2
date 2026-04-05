# frozen_string_literal: true

# Represents a single portal entry extracted from an Ingress damage report email.
PortalRecord = Data.define(:name, :intel_url, :agent_name, :damage, :status)
