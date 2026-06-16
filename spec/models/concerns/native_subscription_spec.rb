require "rails_helper"

# Native in-app subscriptions (Apple, Google Play) alongside Stripe. These
# specs protect the invariants that make IAP safe in this system:
#
# - any-source-unlocks: a subscriber via *any* storefront is entitled
# - encrypted-at-rest: the transaction identity is stored encrypted under the
#   google_id, exactly like the Stripe customer id — so the topological-
#   opacity invariant holds for IAP too
RSpec.describe NativeSubscription do
  let(:google_id) { "google-user-123" }
  let(:resonance) { Resonance.find_or_create_by_google_id(google_id) }

  describe "encrypted storage" do
    it "round-trips the Apple original transaction id through encryption" do
      resonance.apple_original_transaction_id = "2000000000000001"
      resonance.save!

      reloaded = Resonance.find_by_google_id(google_id)
      expect(reloaded.apple_original_transaction_id).to eq("2000000000000001")
    end

    it "round-trips the Google Play purchase token through encryption" do
      resonance.google_play_purchase_token = "play-token-abc"
      resonance.save!

      reloaded = Resonance.find_by_google_id(google_id)
      expect(reloaded.google_play_purchase_token).to eq("play-token-abc")
    end

    # The whole point: the stored column must be ciphertext, never the
    # plaintext transaction id. New IAP fields inherit this by construction.
    it "never stores the transaction identity in plaintext" do
      resonance.apple_original_transaction_id = "2000000000000001"
      resonance.google_play_purchase_token = "play-token-abc"
      resonance.save!

      raw = Resonance.connection.select_one(
        "SELECT encrypted_apple_original_transaction_id, encrypted_google_play_purchase_token " \
        "FROM resonances WHERE encrypted_google_id_hash = #{Resonance.connection.quote(resonance.encrypted_google_id_hash)}"
      )

      expect(raw["encrypted_apple_original_transaction_id"]).not_to include("2000000000000001")
      expect(raw["encrypted_google_play_purchase_token"]).not_to include("play-token-abc")
      expect(raw["encrypted_apple_original_transaction_id"]).to be_present
    end

    it "cannot be decrypted without the google_id" do
      resonance.apple_original_transaction_id = "2000000000000001"
      resonance.save!

      keyless = Resonance.find_by(encrypted_google_id_hash: resonance.encrypted_google_id_hash)
      expect { keyless.apple_original_transaction_id }
        .to raise_error(Resonance::MissingEncryptionKeyError)
    end
  end

  describe "#active_subscription? (any-source-unlocks)" do
    before do
      allow_any_instance_of(Resonance).to receive(:stripe_subscription_active?).and_return(false)
    end

    it "is false with no subscription anywhere" do
      expect(resonance.active_subscription?).to be false
    end

    it "is true when only Stripe is active" do
      allow(resonance).to receive(:stripe_subscription_active?).and_return(true)
      expect(resonance.active_subscription?).to be true
    end

    it "is true when only Apple is active" do
      resonance.apple_original_transaction_id = "2000000000000001"
      resonance.save!
      allow_any_instance_of(AppleAppStore).to receive(:subscription_active?).and_return(true)
      expect(resonance.active_subscription?).to be true
    end

    it "is true when only Google Play is active (and Play is configured)" do
      allow(GooglePlayStore).to receive(:configured?).and_return(true)
      resonance.google_play_purchase_token = "play-token-abc"
      resonance.save!
      allow_any_instance_of(GooglePlayStore).to receive(:subscription_active?).and_return(true)
      expect(resonance.active_subscription?).to be true
    end

    it "ignores Google Play entitlement while Play billing is gated off" do
      # configured? is false in test (no service account) — the Google check
      # short-circuits without hitting the API
      resonance.google_play_purchase_token = "play-token-abc"
      resonance.save!
      expect_any_instance_of(GooglePlayStore).not_to receive(:subscription_active?)
      expect(resonance.google_play_subscription_active?).to be false
    end

    it "does not call a storefront when its identity is absent" do
      # No Apple id stored -> no API call, just false
      expect_any_instance_of(AppleAppStore).not_to receive(:subscription_active?)
      expect(resonance.apple_subscription_active?).to be false
    end
  end

  describe "recording verified purchases" do
    it "persists the Apple identity encrypted" do
      resonance.record_apple_subscription("2000000000000099")
      expect(Resonance.find_by_google_id(google_id).apple_original_transaction_id)
        .to eq("2000000000000099")
    end

    it "persists the Google Play identity encrypted" do
      resonance.record_google_play_subscription("play-token-xyz")
      expect(Resonance.find_by_google_id(google_id).google_play_purchase_token)
        .to eq("play-token-xyz")
    end
  end
end
