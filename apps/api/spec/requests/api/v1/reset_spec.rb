# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DELETE /api/v1/reset", type: :request do
  let(:access_token_store)              { instance_double(UserStore, store: nil) }
  let(:threads_max_internal_date_store) { instance_double(UserStore, delete: 1) }

  before do
    allow(UserStore).to receive(:access_token).and_return(access_token_store)
    allow(UserStore).to receive(:threads_max_internal_date).and_return(threads_max_internal_date_store)
  end

  context "with active session" do
    before { login_as }

    it "returns 204 No Content" do
      delete "/api/v1/reset"

      expect(response).to have_http_status(:no_content)
    end

    it "deletes threads_max_internal_date for the current user" do
      delete "/api/v1/reset"

      expect(threads_max_internal_date_store).to have_received(:delete).with(test_user_id)
    end
  end

  context "without session" do
    it "returns unauthorized" do
      delete "/api/v1/reset"

      expect(response).to have_http_status(:unauthorized)
      expect(threads_max_internal_date_store).not_to have_received(:delete)
    end
  end
end
