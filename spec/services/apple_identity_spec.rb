require "rails_helper"

# AppleIdentity verifies a Sign in with Apple identity token against Apple's
# public keys. These specs sign real tokens with a throwaway RSA key and stub
# the JWKS fetch to return that key's public half — so the full crypto path
# (signature, claims, nonce) is exercised without hitting Apple.
RSpec.describe AppleIdentity do
  let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:jwk) { JWT::JWK.new(rsa_key) }
  let(:client_id) { "fyi.yours.app" }
  let(:raw_nonce) { "device-generated-raw-nonce" }
  subject(:verifier) { described_class.new(config: { client_ids: [ client_id ] }) }

  before do
    # Every instance returns our test key set instead of fetching Apple's.
    allow_any_instance_of(described_class).to receive(:fetch_keys)
      .and_return({ "keys" => [ jwk.export ] })
  end

  def token(claims = {})
    payload = {
      "iss" => "https://appleid.apple.com",
      "aud" => client_id,
      "sub" => "000123.abcdef.4567",
      "exp" => Time.now.to_i + 600,
      "iat" => Time.now.to_i,
      "nonce" => Digest::SHA256.hexdigest(raw_nonce),
      "email" => "someone@privaterelay.appleid.com"
    }.merge(claims)
    JWT.encode(payload, rsa_key, "RS256", { kid: jwk.kid })
  end

  describe "#verify" do
    it "returns the subject and email for a valid token" do
      result = verifier.verify(token, raw_nonce: raw_nonce)
      expect(result.sub).to eq("000123.abcdef.4567")
      expect(result.identity_key).to eq("apple:000123.abcdef.4567")
      expect(result.email).to eq("someone@privaterelay.appleid.com")
    end

    it "rejects a token from the wrong issuer" do
      expect { verifier.verify(token("iss" => "https://evil.example.com"), raw_nonce: raw_nonce) }
        .to raise_error(described_class::VerificationError, /issuer/)
    end

    it "rejects a token for a different audience (not our app)" do
      expect { verifier.verify(token("aud" => "com.someone.else"), raw_nonce: raw_nonce) }
        .to raise_error(described_class::VerificationError, /audience/)
    end

    it "rejects a token whose nonce doesn't match the raw nonce (replay defense)" do
      expect { verifier.verify(token, raw_nonce: "a-different-nonce") }
        .to raise_error(described_class::VerificationError, /nonce/)
    end

    it "rejects an expired token" do
      expect { verifier.verify(token("exp" => Time.now.to_i - 60), raw_nonce: raw_nonce) }
        .to raise_error(described_class::VerificationError, /expired/)
    end

    it "rejects a token signed by a key Apple doesn't publish" do
      other_key = OpenSSL::PKey::RSA.generate(2048)
      forged = JWT.encode(
        { "iss" => "https://appleid.apple.com", "aud" => client_id, "sub" => "x",
          "exp" => Time.now.to_i + 600, "nonce" => Digest::SHA256.hexdigest(raw_nonce) },
        other_key, "RS256", { kid: "unknown-kid" }
      )
      expect { verifier.verify(forged, raw_nonce: raw_nonce) }
        .to raise_error(described_class::VerificationError)
    end

    it "requires an identity token" do
      expect { verifier.verify("", raw_nonce: raw_nonce) }
        .to raise_error(described_class::VerificationError, /token/)
    end

    it "requires a nonce" do
      expect { verifier.verify(token, raw_nonce: "") }
        .to raise_error(described_class::VerificationError, /nonce/i)
    end
  end
end
