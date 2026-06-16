# Release Checklist

This repo does not rely on application boot to run database migrations. Before
deploying a change that requires new database shape, apply the SQL manually to
the target database, then deploy the app code.

## Native iOS subscriptions

Before deploying the native in-app subscription changes to staging or
production:

1. Confirm the GitHub environment has these secrets:
   - `APPLE_IAP_ISSUER_ID`
   - `APPLE_IAP_KEY_ID`
   - `APPLE_IAP_PRIVATE_KEY`
2. Confirm the GitHub environment has these variables:
   - `APPLE_IAP_BUNDLE_ID` (`fyi.yours.app`)
   - `APPLE_IAP_ENVIRONMENT` (`Sandbox` for staging, `Production` for production)
3. Apply the database SQL below to the target database before sending traffic
   to code that reads or writes native subscription fields.
4. Run the Fly secrets workflow or deploy workflow so the Apple IAP values are
   staged onto the Fly app.
5. Deploy the app code.

Run the index statements outside a transaction.

```sql
ALTER TABLE public.resonances
  ADD COLUMN IF NOT EXISTS encrypted_apple_original_transaction_id text,
  ADD COLUMN IF NOT EXISTS encrypted_google_play_purchase_token text;

ALTER TABLE public.resonances
  ADD COLUMN IF NOT EXISTS apple_transaction_fingerprint character varying,
  ADD COLUMN IF NOT EXISTS google_play_transaction_fingerprint character varying;

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS index_resonances_on_apple_transaction_fingerprint
  ON public.resonances USING btree (apple_transaction_fingerprint);

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS index_resonances_on_google_play_transaction_fingerprint
  ON public.resonances USING btree (google_play_transaction_fingerprint);
```

Android remains deferred. Do not submit the Android app to Google Play until
Google Play Billing is enabled end to end and the Android review items in the
PR history are addressed.
