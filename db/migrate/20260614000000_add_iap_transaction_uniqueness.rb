class AddIapTransactionUniqueness < ActiveRecord::Migration[8.1]
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
  def change
    add_column :resonances, :apple_transaction_fingerprint, :string
    add_column :resonances, :google_play_transaction_fingerprint, :string

    add_index :resonances, :apple_transaction_fingerprint, unique: true
    add_index :resonances, :google_play_transaction_fingerprint, unique: true
  end
end
