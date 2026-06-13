require "rails_helper"

# AppleAppStore verifies in-app purchases against the App Store Server API.
# These specs stub Apple's HTTP responses; the contract under test is that we
# only trust what Apple's API confirms, and only for our own products.
RSpec.describe AppleAppStore do
  let(:config) do
    {
      key_id: "KEY123",
      issuer_id: "issuer-uuid",
      private_key: ec_private_key_pem,
      bundle_id: "fyi.yours.app",
      environment: "Production"
    }
  end
  let(:product_ids) { [ "fyi.yours.subscription.tier_1" ] }
  subject(:store) { described_class.new(config: config, product_ids: product_ids) }

  # A throwaway EC key so JWT signing (and thus the bearer token) works in tests
  def ec_private_key_pem
    @ec_private_key_pem ||= OpenSSL::PKey::EC.generate("prime256v1").to_pem
  end

  # Build an unsigned-but-decodable JWS (header.payload.sig). The verifier only
  # reads the payload segment locally to learn the transactionId; authority
  # comes from Apple's API response, which we stub.
  def jws_with(payload)
    header = Base64.urlsafe_encode64({ alg: "ES256" }.to_json, padding: false)
    body = Base64.urlsafe_encode64(payload.to_json, padding: false)
    "#{header}.#{body}.signature"
  end

  def stub_apple(path, status:, body:)
    stub = instance_double(Net::HTTPResponse, code: status.to_s, body: body.to_json)
    allow(stub).to receive(:is_a?).and_return(false)
    allow(stub).to receive(:is_a?).with(Net::HTTPSuccess).and_return(status == 200)
    allow(stub).to receive(:is_a?).with(Net::HTTPNotFound).and_return(status == 404)
    http = instance_double(Net::HTTP)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request) { stub }
    allow(Net::HTTP).to receive(:new).and_return(http)
  end

  describe "#verify" do
    let(:signed_transaction) { jws_with("transactionId" => "2000000000000001") }

    it "returns an active result for a genuine subscription to our product" do
      # First call: transaction lookup. Second: subscription status.
      txn_jws = jws_with("productId" => "fyi.yours.subscription.tier_1",
                         "originalTransactionId" => "2000000000000001")
      responses = [
        { "signedTransactionInfo" => txn_jws },
        { "data" => [ { "lastTransactions" => [ { "status" => 1 } ] } ] }
      ]
      call = 0
      allow(store).to receive(:get) { responses[call].tap { call += 1 } }

      result = store.verify(signed_transaction)
      expect(result).to be_present
      expect(result.original_transaction_id).to eq("2000000000000001")
      expect(result.product_id).to eq("fyi.yours.subscription.tier_1")
      expect(result.active).to be true
    end

    it "returns nil for a product that isn't ours" do
      txn_jws = jws_with("productId" => "com.someone.else.thing")
      allow(store).to receive(:get).and_return({ "signedTransactionInfo" => txn_jws })

      expect(store.verify(signed_transaction)).to be_nil
    end

    it "returns nil when the transaction id can't be read" do
      expect(store.verify("not-a-jws")).to be_nil
    end

    it "reports inactive when Apple shows an expired status" do
      txn_jws = jws_with("productId" => "fyi.yours.subscription.tier_1",
                         "originalTransactionId" => "2000000000000001")
      responses = [
        { "signedTransactionInfo" => txn_jws },
        { "data" => [ { "lastTransactions" => [ { "status" => 2 } ] } ] } # expired
      ]
      call = 0
      allow(store).to receive(:get) { responses[call].tap { call += 1 } }

      expect(store.verify(signed_transaction).active).to be false
    end
  end

  describe "#subscription_active?" do
    it "is true for active/grace/billing-retry statuses" do
      [ 1, 3, 4 ].each do |status|
        allow(store).to receive(:get)
          .and_return({ "data" => [ { "lastTransactions" => [ { "status" => status } ] } ] })
        expect(store.subscription_active?("2000000000000001")).to be(true), "status #{status}"
      end
    end

    it "is false for expired/revoked statuses" do
      [ 2, 5 ].each do |status|
        allow(store).to receive(:get)
          .and_return({ "data" => [ { "lastTransactions" => [ { "status" => status } ] } ] })
        expect(store.subscription_active?("2000000000000001")).to be(false), "status #{status}"
      end
    end
  end
end
