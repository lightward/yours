# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_14_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "resonances", primary_key: "encrypted_google_id_hash", id: :text, force: :cascade do |t|
    t.string "apple_transaction_fingerprint"
    t.text "encrypted_apple_original_transaction_id"
    t.text "encrypted_google_play_purchase_token"
    t.text "encrypted_integration_harmonic_by_night"
    t.text "encrypted_narrative_accumulation_by_day"
    t.text "encrypted_stripe_customer_id"
    t.text "encrypted_textarea"
    t.text "encrypted_universe_day"
    t.string "google_play_transaction_fingerprint"
    t.index ["apple_transaction_fingerprint"], name: "index_resonances_on_apple_transaction_fingerprint", unique: true
    t.index ["google_play_transaction_fingerprint"], name: "index_resonances_on_google_play_transaction_fingerprint", unique: true
  end
end
