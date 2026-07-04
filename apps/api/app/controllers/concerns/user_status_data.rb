# frozen_string_literal: true

module UserStatusData
  private

  def user_status
    {
      spreadsheet_exists:        spreadsheet_exists?,
      last_synced_at:            fetch_int(UserStore.last_synced_at),
      last_processed_at:         fetch_int(UserStore.last_processed_at),
      threads_found:             fetch_int(UserStore.threads_found),
      threads_processed:         fetch_int(UserStore.threads_processed),
      portals_found:             fetch_int(UserStore.portals_found),
      portals_appended:          fetch_int(UserStore.portals_appended),
      threads_max_internal_date: threads_max_internal_date_value,
      scope_expires_at:          {
        spreadsheets: fetch_int(UserStore.scope_spreadsheets),
        sync:         fetch_int(UserStore.scope_sync)
      }
    }
  end

  def spreadsheet_exists?
    !UserStore.spreadsheet_id.fetch_or_nil(current_user_id).nil?
  end

  # Gmail internalDate is in milliseconds; expose a Unix epoch in seconds.
  def threads_max_internal_date_value
    value = UserStore.threads_max_internal_date.fetch_or_nil(current_user_id)
    value && value.to_i / 1000
  end

  # @return [Integer, nil] the stored value as an integer, nil when absent
  def fetch_int(store)
    store.fetch_or_nil(current_user_id)&.to_i
  end
end
