require "rails_helper"

RSpec.describe Resonance, "native app authentication" do
  let(:google_id) { "test-google-id-123" }
  let(:google_id_hash) { Digest::SHA256.hexdigest(google_id) }

  describe ".generate_auth_token" do
    it "generates a token with three dot-separated parts" do
      token = described_class.generate_auth_token(google_id)
      parts = token.split(".")

      expect(parts.length).to eq(3)
    end

    it "includes the google_id_hash as the first part" do
      token = described_class.generate_auth_token(google_id)
      token_hash = token.split(".").first

      expect(token_hash).to eq(google_id_hash)
    end

    it "generates different encrypted portions for the same google_id (due to random IV)" do
      token1 = described_class.generate_auth_token(google_id)
      token2 = described_class.generate_auth_token(google_id)

      encrypted1 = token1.split(".")[1]
      encrypted2 = token2.split(".")[1]

      expect(encrypted1).not_to eq(encrypted2)
    end

    it "generates URL-safe tokens" do
      token = described_class.generate_auth_token(google_id)

      # Should not contain characters that need escaping in URLs
      expect(token).not_to match(%r{[+/=]})
    end
  end

  describe ".find_by_auth_token" do
    let!(:resonance) { described_class.find_or_create_by_google_id(google_id) }
    let(:token) { described_class.generate_auth_token(google_id) }

    it "finds the resonance by valid token" do
      found = described_class.find_by_auth_token(token)

      expect(found).to eq(resonance)
      expect(found.google_id).to eq(google_id)
    end

    it "returns nil for invalid token format" do
      expect(described_class.find_by_auth_token("invalid")).to be_nil
      expect(described_class.find_by_auth_token("one.two")).to be_nil
      expect(described_class.find_by_auth_token("one.two.three.four")).to be_nil
    end

    it "returns nil for tampered token (invalid signature)" do
      parts = token.split(".")
      tampered = "#{parts[0]}.#{parts[1]}.invalidsignature"

      expect(described_class.find_by_auth_token(tampered)).to be_nil
    end

    it "returns nil for tampered encrypted data" do
      parts = token.split(".")
      tampered = "#{parts[0]}.tampereddata.#{parts[2]}"

      expect(described_class.find_by_auth_token(tampered)).to be_nil
    end

    it "returns nil if google_id doesn't correspond to any resonance" do
      token_for_nonexistent = described_class.generate_auth_token("nonexistent-google-id")

      expect(described_class.find_by_auth_token(token_for_nonexistent)).to be_nil
    end

    it "sets google_id on found resonance for decryption" do
      found = described_class.find_by_auth_token(token)

      # Should be able to decrypt fields
      expect { found.universe_day }.not_to raise_error
    end
  end

  describe "token security properties" do
    it "tokens are tied to Rails secret_key_base" do
      token = described_class.generate_auth_token(google_id)

      # Simulate secret rotation by stubbing
      allow(Rails.application).to receive(:secret_key_base).and_return("different-secret")

      # Token should be invalid with different secret
      expect(described_class.find_by_auth_token(token)).to be_nil
    end
  end
end
