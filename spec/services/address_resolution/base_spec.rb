require "rails_helper"

RSpec.describe AddressResolution::Base do
  let(:adapter) { described_class.new(base_url: "https://example.test/") }

  describe "#resolve" do
    it "requires subclasses to implement the method" do
      expect { adapter.resolve("anything") }
        .to raise_error(NotImplementedError, /AddressResolution::Base must implement #resolve/)
    end
  end

  describe "#initialize" do
    it "strips trailing slashes and uses the class defaults" do
      expect(adapter.base_url).to eq("https://example.test")
      expect(adapter.rate_limit_interval).to eq(1.0)
      expect(adapter.user_agent).to eq(AddressResolution::Base::DEFAULT_USER_AGENT)
      expect(adapter.provider_key).to eq("base")
    end

    it "accepts a custom user agent and rate limit interval" do
      custom = described_class.new(
        base_url: "https://example.test",
        user_agent: "ForecastApp/1.0 (custom)",
        rate_limit_interval: 0.25
      )

      expect(custom.user_agent).to eq("ForecastApp/1.0 (custom)")
      expect(custom.rate_limit_interval).to eq(0.25)
    end
  end

  describe "#reset_rate_limit!" do
    it "clears the class rate limit and returns self" do
      described_class.last_request_at = 5.0

      expect(adapter.reset_rate_limit!).to be(adapter)
      expect(described_class.last_request_at).to be_nil
    end
  end

  describe "address building" do
    it "returns nil when latitude is missing" do
      expect(adapter.send(:build_address, latitude: nil, longitude: 1.0)).to be_nil
    end

    it "returns nil when longitude is missing" do
      expect(adapter.send(:build_address, latitude: 1.0, longitude: nil)).to be_nil
    end
  end
end
