class CreateResonances < ActiveRecord::Migration[8.0]
  def change
    create_table :resonances, id: false do |t|
      t.text :encrypted_google_id_hash, null: false, primary_key: true
      t.text :encrypted_stripe_customer_id
      t.text :encrypted_integration_harmonic_by_night
      t.text :encrypted_narrative_accumulation_by_day
      t.text :encrypted_universe_days_lived  # text not integer, since we're storing encrypted data

      # Note the lack of timestamps - per spec
    end
  end
end
