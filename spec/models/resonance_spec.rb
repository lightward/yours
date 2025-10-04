require "rails_helper"

RSpec.describe Resonance, type: :model do
  describe "validations" do
    it "requires encrypted_google_id_hash" do
      resonance = Resonance.new
      expect(resonance).not_to be_valid
      expect(resonance.errors[:encrypted_google_id_hash]).to include("can't be blank")
    end

    it "enforces uniqueness of encrypted_google_id_hash" do
      google_id = "google-user-123"
      Resonance.find_or_create_by_google_id(google_id)

      resonance = Resonance.new(encrypted_google_id_hash: Digest::SHA256.hexdigest(google_id))
      expect(resonance).not_to be_valid
      expect(resonance.errors[:encrypted_google_id_hash]).to include("has already been taken")
    end
  end

  describe ".find_or_create_by_google_id" do
    let(:google_id) { "google-user-123" }

    it "creates a new resonance for a new google_id" do
      expect {
        Resonance.find_or_create_by_google_id(google_id)
      }.to change(Resonance, :count).by(1)
    end

    it "finds an existing resonance for an existing google_id" do
      resonance = Resonance.find_or_create_by_google_id(google_id)

      expect {
        found_resonance = Resonance.find_or_create_by_google_id(google_id)
        expect(found_resonance.id).to eq(resonance.id)
      }.not_to change(Resonance, :count)
    end

    it "stores a hash of the google_id, not the google_id itself" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      expected_hash = Digest::SHA256.hexdigest(google_id)

      expect(resonance.google_id_hash).to eq(expected_hash)
    end
  end

  describe "encryption" do
    let(:google_id) { "test-google-id" }

    it "encrypts sensitive fields using Google ID as key" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      resonance.stripe_customer_id = "cus_123"
      resonance.integration_harmonic_by_night = "harmonic data"
      resonance.narrative_accumulation_by_day = "narrative data"
      resonance.universe_days_lived = 42
      resonance.save!

      # Verify data is encrypted in the database
      raw_record = ActiveRecord::Base.connection.execute(
        "SELECT * FROM resonances WHERE encrypted_google_id_hash = '#{resonance.encrypted_google_id_hash}'"
      ).first

      expect(raw_record["encrypted_stripe_customer_id"]).to be_present
      expect(raw_record["encrypted_stripe_customer_id"]).not_to eq("cus_123")
      expect(raw_record["encrypted_integration_harmonic_by_night"]).not_to eq("harmonic data")
      expect(raw_record["encrypted_narrative_accumulation_by_day"]).not_to eq("narrative data")
    end

    it "can decrypt data with the correct Google ID" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      resonance.stripe_customer_id = "cus_123"
      resonance.universe_days_lived = 42
      resonance.save!

      # Reload and decrypt with correct Google ID
      reloaded = Resonance.find_by_google_id(google_id)
      expect(reloaded.stripe_customer_id).to eq("cus_123")
      expect(reloaded.universe_days_lived).to eq(42)
    end

    it "cannot decrypt data without Google ID" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      resonance.stripe_customer_id = "cus_123"
      resonance.save!

      # Attempt to decrypt without Google ID - find by primary key
      reloaded = Resonance.find_by(encrypted_google_id_hash: resonance.encrypted_google_id_hash)
      expect(reloaded.stripe_customer_id).to be_nil
    end
  end
end
