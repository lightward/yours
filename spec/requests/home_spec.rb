require 'rails_helper'

RSpec.describe "Homes", type: :request do
  before do
    host! "test.host"
  end

  describe "GET /home" do
    it "returns http success" do
      get home_path
      expect(response).to have_http_status(:success)
    end
  end
end
