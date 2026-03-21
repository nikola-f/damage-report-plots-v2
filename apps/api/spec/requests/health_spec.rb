require 'rails_helper'

RSpec.describe "GET /up", type: :request do
  it "returns 200 OK with response body" do
    get "/up"

    expect(response).to have_http_status(:ok)
    expect(response.body).to be_present
    expect(response.content_type).to include('text/html')
  end
end
