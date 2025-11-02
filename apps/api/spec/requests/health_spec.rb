require 'rails_helper'

RSpec.describe "Health Check", type: :request do
  describe "GET /up" do
    it "returns http success" do
      get "/up"
      expect(response).to have_http_status(:success)
    end

    it "returns 200 OK" do
      get "/up"
      expect(response.status).to eq(200)
    end
  end
end
