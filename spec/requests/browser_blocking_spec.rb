require "rails_helper"

RSpec.describe "Browser blocking", type: :request do
  before do
    host! "test.host"
  end

  # Modern browser user agent (Chrome 120+)
  let(:modern_user_agent) { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" }

  # Old browser user agent (Chrome 60)
  let(:old_user_agent) { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.0.0 Safari/537.36" }

  describe "routes that allow non-modern browsers" do
    describe "GET /" do
      it "allows modern browsers" do
        get root_path, headers: { "HTTP_USER_AGENT" => modern_user_agent }
        expect(response).to have_http_status(:success)
      end

      it "allows non-modern browsers (for social media crawlers)" do
        get root_path, headers: { "HTTP_USER_AGENT" => old_user_agent }
        expect(response).to have_http_status(:success)
      end
    end

    describe "GET /llms.txt" do
      it "allows modern browsers" do
        get "/llms.txt", headers: { "HTTP_USER_AGENT" => modern_user_agent }
        expect(response).to have_http_status(:success)
      end

      it "allows non-modern browsers (for LLM crawlers)" do
        get "/llms.txt", headers: { "HTTP_USER_AGENT" => old_user_agent }
        expect(response).to have_http_status(:success)
        expect(response.body).to include("# Yours 無")
      end
    end
  end

  describe "routes that block non-modern browsers" do
    describe "GET /exit" do
      it "allows modern browsers" do
        get exit_path, headers: { "HTTP_USER_AGENT" => modern_user_agent }
        expect(response).to redirect_to(root_path)
      end

      it "blocks non-modern browsers" do
        get exit_path, headers: { "HTTP_USER_AGENT" => old_user_agent }
        expect(response).to have_http_status(:not_acceptable)
        expect(response.body).to include("browser")
      end
    end

    describe "GET /settings" do
      it "allows modern browsers (redirects to root because not authenticated)" do
        get settings_path, headers: { "HTTP_USER_AGENT" => modern_user_agent }
        expect(response).to redirect_to(root_path)
      end

      it "blocks non-modern browsers" do
        get settings_path, headers: { "HTTP_USER_AGENT" => old_user_agent }
        expect(response).to have_http_status(:not_acceptable)
      end
    end

    describe "POST /stream" do
      let(:message) do
        {
          role: "user",
          content: [ { type: "text", text: "Hello" } ]
        }
      end

      it "allows modern browsers (redirects because not authenticated)" do
        post stream_path, params: { message: message }, headers: { "HTTP_USER_AGENT" => modern_user_agent }
        expect(response).to redirect_to(root_path)
      end

      it "blocks non-modern browsers" do
        post stream_path, params: { message: message }, headers: { "HTTP_USER_AGENT" => old_user_agent }
        expect(response).to have_http_status(:not_acceptable)
      end
    end

    describe "GET /sleep" do
      it "allows modern browsers (redirects because not authenticated)" do
        get sleep_path, headers: { "HTTP_USER_AGENT" => modern_user_agent }
        expect(response).to redirect_to(root_path)
      end

      it "blocks non-modern browsers" do
        get sleep_path, headers: { "HTTP_USER_AGENT" => old_user_agent }
        expect(response).to have_http_status(:not_acceptable)
      end
    end

    describe "PUT /textarea" do
      it "allows modern browsers (returns 401 because not authenticated)" do
        put textarea_path, params: { textarea: "test" }, headers: { "HTTP_USER_AGENT" => modern_user_agent }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it "blocks non-modern browsers" do
        put textarea_path, params: { textarea: "test" }, headers: { "HTTP_USER_AGENT" => old_user_agent }, as: :json
        expect(response).to have_http_status(:not_acceptable)
      end
    end

    describe "POST /subscription" do
      it "allows modern browsers (redirects because not authenticated)" do
        post subscription_path, params: { tier: "tier_1" }, headers: { "HTTP_USER_AGENT" => modern_user_agent }
        expect(response).to redirect_to(root_path)
      end

      it "blocks non-modern browsers" do
        post subscription_path, params: { tier: "tier_1" }, headers: { "HTTP_USER_AGENT" => old_user_agent }
        expect(response).to have_http_status(:not_acceptable)
      end
    end

    describe "DELETE /subscription" do
      it "allows modern browsers (redirects because not authenticated)" do
        delete subscription_path, headers: { "HTTP_USER_AGENT" => modern_user_agent }
        expect(response).to redirect_to(root_path)
      end

      it "blocks non-modern browsers" do
        delete subscription_path, headers: { "HTTP_USER_AGENT" => old_user_agent }
        expect(response).to have_http_status(:not_acceptable)
      end
    end

    describe "POST /reset" do
      it "allows modern browsers (redirects because not authenticated)" do
        post reset_path, headers: { "HTTP_USER_AGENT" => modern_user_agent }
        expect(response).to redirect_to(root_path)
      end

      it "blocks non-modern browsers" do
        post reset_path, headers: { "HTTP_USER_AGENT" => old_user_agent }
        expect(response).to have_http_status(:not_acceptable)
      end
    end
  end
end
