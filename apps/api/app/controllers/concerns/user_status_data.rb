# frozen_string_literal: true

module UserStatusData
  private

  def user_status
    {
      spreadsheet_exists: spreadsheet_exists?,
      last_synced_at:     last_synced_at_value,
      threads_found:      fetch_count(UserStore.threads_found),
      threads_processed:  fetch_count(UserStore.threads_processed),
      portals_found:              fetch_count(UserStore.portals_found),
      portals_appended:           fetch_count(UserStore.portals_appended),
      threads_max_internal_date:  threads_max_internal_date_value,
      scope_expires_at:           {
        spreadsheets: scope_expires_at_value(UserStore.scope_spreadsheets),
        sync:         scope_expires_at_value(UserStore.scope_sync)
      }
    }
  end

  def spreadsheet_exists?
    UserStore.spreadsheet_id.fetch(current_user_id)
    true
  rescue KeyError
    false
  end

  def last_synced_at_value
    UserStore.last_synced_at.fetch(current_user_id).to_i
  rescue KeyError
    nil
  end

  def scope_expires_at_value(store)
    store.fetch(current_user_id).to_i
  rescue KeyError
    nil
  end

  def threads_max_internal_date_value
    UserStore.threads_max_internal_date.fetch(current_user_id).to_i / 1000
  rescue KeyError
    nil
  end

  def fetch_count(store)
    store.fetch(current_user_id).to_i
  rescue KeyError
    nil
  end
end
