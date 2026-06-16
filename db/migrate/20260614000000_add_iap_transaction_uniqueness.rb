class AddIapTransactionUniqueness < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Closes the cross-account IAP replay hole: a verified Apple/Google
  # transaction must bind to exactly one resonance, so the same signed
  # transaction can't unlock multiple accounts.
  #
  # We can't index the encrypted_* identity columns (they're per-record
  # ciphertext — the same transaction id encrypts differently under each
  # resonance's key, so a unique index there would never collide). Instead we
  # store a *keyed, deterministic* hash of the transaction identifier in a
  # plaintext column and make THAT unique. The hash is keyed with the app
  # secret (HMAC), so it reveals nothing about the transaction id on its own,
  # but the same transaction id always produces the same hash — which is what
  # lets the database reject a second account claiming it.
  def up
    execute <<~SQL
      ALTER TABLE public.resonances
        ADD COLUMN IF NOT EXISTS apple_transaction_fingerprint character varying,
        ADD COLUMN IF NOT EXISTS google_play_transaction_fingerprint character varying
    SQL

    execute <<~SQL
      CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS index_resonances_on_apple_transaction_fingerprint
        ON public.resonances USING btree (apple_transaction_fingerprint)
    SQL

    execute <<~SQL
      CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS index_resonances_on_google_play_transaction_fingerprint
        ON public.resonances USING btree (google_play_transaction_fingerprint)
    SQL
  end

  def down
    execute <<~SQL
      DROP INDEX CONCURRENTLY IF EXISTS public.index_resonances_on_google_play_transaction_fingerprint
    SQL

    execute <<~SQL
      DROP INDEX CONCURRENTLY IF EXISTS public.index_resonances_on_apple_transaction_fingerprint
    SQL

    execute <<~SQL
      ALTER TABLE public.resonances
        DROP COLUMN IF EXISTS google_play_transaction_fingerprint,
        DROP COLUMN IF EXISTS apple_transaction_fingerprint
    SQL
  end
end
