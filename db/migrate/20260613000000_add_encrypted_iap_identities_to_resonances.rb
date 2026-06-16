class AddEncryptedIapIdentitiesToResonances < ActiveRecord::Migration[8.1]
  # Native in-app subscription identities, stored encrypted under the
  # google_id exactly like encrypted_stripe_customer_id — so the
  # topological-opacity invariant holds: without the OAuth key, the server
  # can't link an Apple/Google transaction to a resonance.
  def up
    execute <<~SQL
      ALTER TABLE public.resonances
        ADD COLUMN IF NOT EXISTS encrypted_apple_original_transaction_id text,
        ADD COLUMN IF NOT EXISTS encrypted_google_play_purchase_token text
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE public.resonances
        DROP COLUMN IF EXISTS encrypted_apple_original_transaction_id,
        DROP COLUMN IF EXISTS encrypted_google_play_purchase_token
    SQL
  end
end
