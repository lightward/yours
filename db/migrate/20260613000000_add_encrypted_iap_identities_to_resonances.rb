class AddEncryptedIapIdentitiesToResonances < ActiveRecord::Migration[8.1]
  # Native in-app subscription identities, stored encrypted under the
  # google_id exactly like encrypted_stripe_customer_id — so the
  # topological-opacity invariant holds: without the OAuth key, the server
  # can't link an Apple/Google transaction to a resonance.
  def change
    add_column :resonances, :encrypted_apple_original_transaction_id, :text
    add_column :resonances, :encrypted_google_play_purchase_token, :text
  end
end
