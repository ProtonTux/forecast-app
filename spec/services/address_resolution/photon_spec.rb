require "rails_helper"

RSpec.describe AddressResolution::Photon do
  let(:base_url) { "https://photon.komoot.io" }
  let(:search_url) { %r{\A#{Regexp.escape(base_url)}/api\?} }
  let(:query) do
    "1801 West International Speedway Blvd, Daytona Beach, Florida, United States 32114"
  end

  let(:feature) do
    {
      "type" => "Feature",
      "properties" => {
        "osm_type" => "N",
        "osm_id" => 10_583_204_936,
        "osm_key" => "tourism",
        "osm_value" => "museum",
        "type" => "house",
        "housenumber" => "1801",
        "name" => "Motorsports Hall of Fame of America",
        "street" => "West International Speedway Boulevard",
        "city" => "Daytona Beach",
        "county" => "Volusia",
        "state" => "Florida",
        "country" => "United States",
        "postcode" => "32114",
        "countrycode" => "us"
      },
      "geometry" => {
        "type" => "Point",
        "coordinates" => [ -81.0682306, 29.191679 ]
      }
    }
  end

  let(:payload) { { "type" => "FeatureCollection", "features" => [ feature ] } }

  def stub_search(body = payload, status: 200, **keyword_body)
    body = keyword_body unless keyword_body.empty?
    stub_request(:get, search_url)
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "#resolve" do
    it "maps a Photon feature into a ResolvedAddress" do
      stub_search

      address = described_class.new.resolve(query)

      expect(address).to be_a(ResolvedAddress)
      expect(address).to have_attributes(
        zip_code: "32114",
        country_code: "US",
        city: "Daytona Beach",
        region_state: "Florida",
        timezone: nil,
        geocoding_source: "photon"
      )
      expect(address.latitude).to be_within(0.0001).of(29.191679)
      expect(address.longitude).to be_within(0.0001).of(-81.0682306)
      expect(address.geocoded_at).to be_within(5.seconds).of(Time.current)
    end

    it "sends the required search parameters and headers" do
      stub_search

      described_class.new(user_agent: "ForecastApp/1.0 (spec)").resolve(query)

      expect(
        a_request(:get, search_url).with(
          query: hash_including("q" => query, "limit" => "1", "lang" => "en")
        ).with do |request|
          request.headers["User-Agent"] == "ForecastApp/1.0 (spec)" &&
            request.headers["Accept"] == "application/json"
        end
      ).to have_been_made.once
    end

    it "falls back through the available locality fields" do
      stub_search(
        "features" => [ {
          "properties" => { "town" => "Example Town", "county" => "Example County" },
          "geometry" => { "coordinates" => [ 2.5, 1.5 ] }
        } ]
      )

      address = described_class.new.resolve("Example")

      expect(address).to have_attributes(
        city: "Example Town",
        region_state: "Example County",
        zip_code: nil,
        country_code: nil
      )
    end

    it "falls back to the feature name when no locality field is present" do
      stub_search(
        "features" => [ {
          "properties" => { "name" => "Example Place" },
          "geometry" => { "coordinates" => [ 2.5, 1.5 ] }
        } ]
      )

      expect(described_class.new.resolve("Example").city).to eq("Example Place")
    end

    it "returns nil when there are no features" do
      stub_search("features" => [])

      expect(described_class.new.resolve(query)).to be_nil
    end

    it "returns nil when the payload has no feature collection" do
      stub_search({ "unexpected" => true })

      expect(described_class.new.resolve(query)).to be_nil
    end

    it "returns nil when the first feature is not a hash" do
      stub_search("features" => [ nil ])

      expect(described_class.new.resolve(query)).to be_nil
    end

    it "returns nil when the geometry has no coordinates" do
      stub_search("features" => [ { "properties" => { "city" => "Nowhere" } } ])

      expect(described_class.new.resolve("Nowhere")).to be_nil
    end

    it "returns nil when the coordinates are not an array" do
      stub_search(
        "features" => [ {
          "properties" => { "city" => "Nowhere" },
          "geometry" => { "coordinates" => "not-an-array" }
        } ]
      )

      expect(described_class.new.resolve("Nowhere")).to be_nil
    end

    it "returns nil when the coordinates are not numeric" do
      stub_search(
        "features" => [ {
          "properties" => { "city" => "Nowhere" },
          "geometry" => { "coordinates" => [ "east", "north" ] }
        } ]
      )

      expect(described_class.new.resolve("Nowhere")).to be_nil
    end
  end

  describe "configuration" do
    it "uses a custom base URL and strips trailing slashes" do
      custom_url = %r{\Ahttps://photon.example.test/api\?}
      stub_request(:get, custom_url).to_return(status: 200, body: payload.to_json)

      adapter = described_class.new(base_url: "https://photon.example.test/")

      expect(adapter.base_url).to eq("https://photon.example.test")
      adapter.resolve(query)
      expect(a_request(:get, custom_url)).to have_been_made.once
    end

    it "defaults to one request per second" do
      expect(described_class.new.rate_limit_interval).to eq(1.0)
    end

    it "identifies itself as the photon provider" do
      expect(described_class.new.provider_key).to eq("photon")
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
        .to raise_error(AddressResolver::Error, /Photon request failed with 503/)
    end

    it "raises an error for invalid JSON" do
      stub_request(:get, search_url).to_return(status: 200, body: "{not-json")

      expect { described_class.new.resolve(query) }
        .to raise_error(AddressResolver::Error, /Photon returned invalid JSON/)
    end

    it "raises an error when the request times out" do
      stub_request(:get, search_url).to_timeout

      expect { described_class.new.resolve(query) }
        .to raise_error(AddressResolver::Error, /Photon request failed/)
    end
  end
end
