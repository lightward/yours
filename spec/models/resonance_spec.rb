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
      resonance.universe_day = 42
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
      resonance.universe_day = 42
      resonance.save!

      # Reload and decrypt with correct Google ID
      reloaded = Resonance.find_by_google_id(google_id)
      expect(reloaded.stripe_customer_id).to eq("cus_123")
      expect(reloaded.universe_day).to eq(42)
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

  describe "#universe_day" do
    let(:google_id) { "google-user-123" }

    it "returns 1 for new resonance" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      expect(resonance.universe_day).to eq(1)
    end

    it "returns the set value for existing resonance" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      resonance.universe_day = 42
      resonance.save!

      reloaded = Resonance.find_by_google_id(google_id)
      expect(reloaded.universe_day).to eq(42)
    end
  end

  describe "narrative_accumulation_by_day" do
    let(:google_id) { "google-user-123" }

    it "stores and retrieves JSON array of messages" do
      resonance = Resonance.find_or_create_by_google_id(google_id)

      messages = [
        { "role" => "user", "content" => [ { "type" => "text", "text" => "Hello" } ] },
        { "role" => "assistant", "content" => [ { "type" => "text", "text" => "Hi there!" } ] }
      ]

      resonance.narrative_accumulation_by_day = messages
      resonance.save!

      reloaded = Resonance.find_by_google_id(google_id)
      expect(reloaded.narrative_accumulation_by_day).to eq(messages)
    end

    it "returns empty array when nil" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      expect(resonance.narrative_accumulation_by_day).to eq([])
    end

    it "encrypts the data" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      messages = [ { role: "user", content: [ { type: "text", text: "Secret" } ] } ]

      resonance.narrative_accumulation_by_day = messages
      resonance.save!

      expect(resonance.encrypted_narrative_accumulation_by_day).not_to include("Secret")
      expect(resonance.encrypted_narrative_accumulation_by_day).to be_present
    end
  end

  describe "#universe_time" do
    let(:google_id) { "google-user-123" }

    it "returns day:message_count format" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      resonance.universe_day = 3
      resonance.narrative_accumulation_by_day = [
        { role: "user", content: [ { type: "text", text: "Message 1" } ] },
        { role: "assistant", content: [ { type: "text", text: "Response 1" } ] },
        { role: "user", content: [ { type: "text", text: "Message 2" } ] }
      ]

      expect(resonance.universe_time).to eq("3:3")
    end

    it "returns day:0 for new day with no messages" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      expect(resonance.universe_time).to eq("1:0")
    end

    it "increments with each message" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      resonance.narrative_accumulation_by_day = []

      expect(resonance.universe_time).to eq("1:0")

      messages = resonance.narrative_accumulation_by_day
      messages << { role: "user", content: [ { type: "text", text: "Hi" } ] }
      resonance.narrative_accumulation_by_day = messages
      expect(resonance.universe_time).to eq("1:1")

      messages << { role: "assistant", content: [ { type: "text", text: "Hello" } ] }
      resonance.narrative_accumulation_by_day = messages
      expect(resonance.universe_time).to eq("1:2")
    end

    it "is monotonically increasing" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      resonance.narrative_accumulation_by_day = []

      time1 = resonance.universe_time

      messages = resonance.narrative_accumulation_by_day
      messages << { role: "user", content: [ { type: "text", text: "Hi" } ] }
      resonance.narrative_accumulation_by_day = messages
      time2 = resonance.universe_time

      resonance.universe_day = 2
      resonance.narrative_accumulation_by_day = []
      time3 = resonance.universe_time

      # Compare as "day:count" strings
      day1, count1 = time1.split(":").map(&:to_i)
      day2, count2 = time2.split(":").map(&:to_i)
      day3, count3 = time3.split(":").map(&:to_i)

      expect(day2 > day1 || (day2 == day1 && count2 > count1)).to be true
      expect(day3 > day2 || (day3 == day2 && count3 > count2)).to be true
    end
  end

  describe "universe_day validation" do
    let(:google_id) { "google-user-123" }

    it "prevents universe_day from decreasing" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      resonance.universe_day = 5
      resonance.save!

      resonance.universe_day = 3
      expect(resonance).not_to be_valid
      expect(resonance.errors[:universe_day]).to include("cannot decrease (was 5, attempted 3)")
    end

    it "allows universe_day to increase" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      resonance.universe_day = 5
      resonance.save!

      resonance.universe_day = 7
      expect(resonance).to be_valid
    end

    it "allows universe_day to stay the same" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      resonance.universe_day = 5
      resonance.save!

      resonance.narrative_accumulation_by_day = [ { role: "user", content: [ { type: "text", text: "hi" } ] } ]
      expect(resonance).to be_valid
    end

    it "allows setting universe_day on new record" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      resonance.universe_day = 1
      expect(resonance).to be_valid
    end
  end
end
