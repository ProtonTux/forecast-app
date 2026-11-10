require "rails_helper"

RSpec.describe AddressResolution::OpenMeteo do
  let(:base_url) { "https://geocoding-api.open-meteo.com" }
  let(:search_url) { %r{\A#{Regexp.escape(base_url)}/v1/search\?} }
  let(:query) { "1801 West International Speedway Blvd, Daytona Beach, Florida, United States 32114" }

  let(:result) do
    {
      "id" => 4_152_872,
      "name" => "Daytona Beach",
      "latitude" => 29.21081,
      "longitude" => -81.02283,
      "elevation" => 4.0,
      "feature_code" => "PPL",
      "country_code" => "us",
      "timezone" => "America/New_York",
      "population" => 72_647,
      "postcodes" => [ "32114", "32115" ],
      "country" => "United States",
      "admin1" => "Florida",
      "admin2" => "Volusia"
    }
  end

  let(:payload) { { "results" => [ result ] } }

  def stub_search(body = payload, status: 200, **keyword_body)
    body = keyword_body unless keyword_body.empty?
    stub_request(:get, search_url)
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "#resolve" do
    it "maps an Open-Meteo result into a ResolvedAddress" do
      stub_search

      address = described_class.new.resolve(query)

      expect(address).to be_a(ResolvedAddress)
      expect(address).to have_attributes(
        zip_code: "32114",
        country_code: "US",
        city: "Daytona Beach",
        region_state: "Florida",
        timezone: "America/New_York",
        geocoding_source: "open_meteo"
      )
      expect(address.latitude).to be_within(0.0001).of(29.21081)
      expect(address.longitude).to be_within(0.0001).of(-81.02283)
      expect(address.geocoded_at).to be_within(5.seconds).of(Time.current)
    end

    it "sends the required search parameters and headers" do
      stub_search

      described_class.new(user_agent: "ForecastApp/1.0 (spec)").resolve(query)

      expect(
        a_request(:get, search_url).with(
          query: hash_including(
            "name" => query,
            "count" => "1",
            "language" => "en",
            "format" => "json"
          )
        ).with do |request|
          request.headers["User-Agent"] == "ForecastApp/1.0 (spec)" &&
            request.headers["Accept"] == "application/json"
        end
      ).to have_been_made.once
    end

    it "falls back to a single postcode field" do
      stub_search("results" => [ result.except("postcodes").merge("postcode" => "90210") ])

      expect(described_class.new.resolve("Beverly Hills").zip_code).to eq("90210")
    end

    it "falls back to admin2 when admin1 is missing" do
      stub_search("results" => [ result.except("admin1") ])

      expect(described_class.new.resolve(query).region_state).to eq("Volusia")
    end

    it "returns nil when results are missing" do
      stub_search({ "generationtime_ms" => 0.13 })

      expect(described_class.new.resolve(query)).to be_nil
    end

    it "returns nil when results are empty" do
      stub_search("results" => [])

      expect(described_class.new.resolve(query)).to be_nil
    end

    it "returns nil when results are not an array" do
      stub_search("results" => "unexpected")

      expect(described_class.new.resolve(query)).to be_nil
    end

    it "returns nil when the first result is not a hash" do
      stub_search("results" => [ nil ])

      expect(described_class.new.resolve(query)).to be_nil
    end

    it "returns nil when the result has no coordinates" do
      stub_search("results" => [ { "name" => "Nowhere" } ])

      expect(described_class.new.resolve("Nowhere")).to be_nil
    end

    it "returns nil when the coordinates are not numeric" do
      stub_search("results" => [ { "name" => "Nowhere", "latitude" => "north", "longitude" => "east" } ])

      expect(described_class.new.resolve("Nowhere")).to be_nil
    end
  end

  describe "configuration" do
    it "uses a custom base URL and strips trailing slashes" do
      custom_url = %r{\Ahttps://geocoding.example.test/v1/search\?}
      stub_request(:get, custom_url).to_return(status: 200, body: payload.to_json)

      adapter = described_class.new(base_url: "https://geocoding.example.test/")

      expect(adapter.base_url).to eq("https://geocoding.example.test")
      adapter.resolve(query)
      expect(a_request(:get, custom_url)).to have_been_made.once
    end

    it "defaults to a short rate limit interval" do
      expect(described_class.new.rate_limit_interval).to eq(0.1)
    end

    it "identifies itself as the open_meteo provider" do
      expect(described_class.new.provider_key).to eq("open_meteo")
    end

    it "resets its rate limit" do
      described_class.last_request_at = 123.0
      adapter = described_class.new

      expect(adapter.reset_rate_limit!).to be(adapter)
      expect(described_class.last_request_at).to be_nil
    end
  end

  describe "error handling" do
    it "raises an error for a non-success response" do
      stub_search({}, status: 503)

      expect { described_class.new.resolve(query) }
        .to raise_error(AddressResolver::Error, /Open-Meteo Geocoding request failed with 503/)
    end

    it "raises an error for invalid JSON" do
      stub_request(:get, search_url).to_return(status: 200, body: "{not-json")

      expect { described_class.new.resolve(query) }
        .to raise_error(AddressResolver::Error, /Open-Meteo Geocoding returned invalid JSON/)
    end

    it "raises an error when the request times out" do
      stub_request(:get, search_url).to_timeout

      expect { described_class.new.resolve(query) }
        .to raise_error(AddressResolver::Error, /Open-Meteo Geocoding request failed/)
    end
  end
end
