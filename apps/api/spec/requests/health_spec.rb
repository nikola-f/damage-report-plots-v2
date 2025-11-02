require 'rails_helper'

RSpec.describe "GET /up", type: :request do
  it "returns http success" do
    get "/up"
    expect(response).to have_http_status(:success)
  end

  it "returns 200 OK" do
    get "/up"
    expect(response.status).to eq(200)
  end
end
