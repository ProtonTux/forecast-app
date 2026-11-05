require "rails_helper"

RSpec.describe Weather::Providers::Base do
  let(:normalizer) { instance_double(Weather::Normalizer) }
  let(:provider) { described_class.new(normalizer: normalizer) }

  describe ".provider_name" do
    it "derives a snake_case provider name from the class name" do
      expect(Weather::Providers::Noaa.provider_name).to eq("noaa")
      expect(Weather::Providers::OpenMeteo.provider_name).to eq("open_meteo")
    end
  end

  describe "#name" do
    it "returns the provider name" do
      expect(provider.name).to eq("base")
    end
  end

  describe "#forecast" do
    it "delegates fetching and normalization through the common interface" do
      payload = { "raw" => true }
      allow(provider).to receive(:fetch).with(latitude: 1.0, longitude: 2.0).and_return(payload)
      allow(normalizer).to receive(:call).with(provider: "base", payload: payload).and_return(:normalized)

      expect(provider.forecast(latitude: 1.0, longitude: 2.0)).to eq(:normalized)
    end
  end

  describe "#fetch" do
    it "must be implemented by subclasses" do
      expect { provider.send(:fetch, latitude: 1.0, longitude: 2.0) }
        .to raise_error(NotImplementedError, /must implement #fetch/)
    end
  end

  describe "#configured?" do
    it "is enabled by default" do
      expect(provider.configured?).to be(true)
    end
  end

  describe "supplied HTTP clients" do
    let(:url) { "https://example.com/forecast" }

    it "uses a get_json client when available" do
      client = double("HttpClient")
      allow(client).to receive(:get_json).and_return("ok" => true)
      provider = described_class.new(normalizer: normalizer, http_client: client)

      expect(provider.send(:get_json, url)).to eq("ok" => true)
      expect(client).to have_received(:get_json).with(url, headers: {})
    end

    it "uses a get client when get_json is unavailable" do
      client = double("HttpClient")
      allow(client).to receive(:get).and_return("ok" => true)
      provider = described_class.new(normalizer: normalizer, http_client: client)

      expect(provider.send(:get_json, url)).to eq("ok" => true)
      expect(client).to have_received(:get).with(url, headers: {})
    end
  end

  describe "default user agent" do
    it "returns the application default" do
      expect(provider.send(:default_user_agent)).to include("ForecastApp")
    end
  end

  describe "default HTTP client" do
    let(:url) { "https://example.com/forecast" }

    it "parses successful JSON responses" do
      stub_request(:get, url).to_return(status: 200, body: { "ok" => true }.to_json)

      expect(provider.send(:get_json, url)).to eq("ok" => true)
    end

    it "sends the configured User-Agent and Accept headers" do
      stub_request(:get, url).to_return(status: 200, body: "{}")

      provider.send(:get_json, url)

      expect(
        a_request(:get, url).with do |request|
          request.headers["User-Agent"].to_s.include?("ForecastApp") &&
            request.headers["Accept"].to_s.include?("application/geo+json")
        end
      ).to have_been_made
    end

    it "wraps non-success responses in a provider error" do
      stub_request(:get, url).to_return(status: 503, body: "Service Unavailable")

      expect { provider.send(:get_json, url) }
        .to raise_error(Weather::Providers::Error, /base request failed with 503/)
    end

    it "wraps invalid JSON in a provider error" do
      stub_request(:get, url).to_return(status: 200, body: "not json")

      expect { provider.send(:get_json, url) }
        .to raise_error(Weather::Providers::Error, /base returned invalid JSON/)
    end

    it "wraps network failures in a provider error" do
      stub_request(:get, url).to_raise(SocketError.new("getaddrinfo failed"))

      expect { provider.send(:get_json, url) }
        .to raise_error(Weather::Providers::Error, /base request failed/)
    end
  end
end
