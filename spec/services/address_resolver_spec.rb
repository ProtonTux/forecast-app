require "rails_helper"

RSpec.describe AddressResolver do
  let(:base_url) { "https://nominatim.openstreetmap.org" }
  let(:search_url) { %r{\A#{Regexp.escape(base_url)}/search\?} }
  let(:query) do
    "1801 West International Speedway Blvd, Daytona Beach, Florida, United States 32114"
  end
  let(:normalized_query) { query.downcase }
  let(:messy_query) do
    "  1801   West International Speedway Blvd, Daytona Beach, Florida, United States 32114  "
  end

  let(:result) do
    {
      "lat" => "29.1858",
      "lon" => "-81.0700",
      "address" => {
        "postcode" => "32114",
        "country_code" => "us",
        "city" => "Daytona Beach",
        "state" => "Florida"
      }
    }
  end

  def stub_search(body = [ result ], status: 200)
    stub_request(:get, search_url)
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "#resolve" do
    it "resolves an address and maps the Nominatim fields" do
      stub_search

      address = described_class.new.resolve(
        query
      )

      expect(address).to be_a(ResolvedAddress)
      expect(address).to have_attributes(
        zip_code: "32114",
        country_code: "US",
        city: "Daytona Beach",
        region_state: "Florida",
        geocoding_source: "nominatim"
      )
      expect(address.latitude).to be_within(0.0001).of(29.1858)
      expect(address.longitude).to be_within(0.0001).of(-81.0700)
      expect(address.geocoded_at).to be_within(5.seconds).of(Time.current)
    end

    it "sends a descriptive User-Agent and the required search parameters" do
      stub_search

      described_class.new(user_agent: "ForecastApp/1.0 (spec)").resolve(
        query
      )

      expect(
        a_request(:get, search_url).with(
          query: hash_including(
            "q" => normalized_query,
            "format" => "jsonv2",
            "addressdetails" => "1",
            "limit" => "1"
          )
        ).with do |request|
          request.headers["User-Agent"] == "ForecastApp/1.0 (spec)" &&
            request.headers["Accept"] == "application/json"
        end
      ).to have_been_made.once
    end

    it "normalizes the query before sending it" do
      stub_search

      described_class.new.resolve(
        messy_query
      )

      expect(
        a_request(:get, search_url).with(
          query: hash_including("q" => normalized_query)
        )
      ).to have_been_made.once
    end

    it "retries without a country name when the first search has no results" do
      fallback_query = normalized_query.sub(", united states", ",")
      json_headers = { "Content-Type" => "application/json" }

      stub_request(:get, search_url)
        .with(query: hash_including("q" => normalized_query))
        .to_return(status: 200, body: [].to_json, headers: json_headers)
      stub_request(:get, search_url)
        .with(query: hash_including("q" => fallback_query))
        .to_return(status: 200, body: [ result ].to_json, headers: json_headers)

      address = described_class.new.resolve(query)

      expect(address).to have_attributes(zip_code: "32114", city: "Daytona Beach")
      expect(
        a_request(:get, search_url).with(query: hash_including("q" => normalized_query))
      ).to have_been_made.once
      expect(
        a_request(:get, search_url).with(query: hash_including("q" => fallback_query))
      ).to have_been_made.once
    end

    [ "Brazil", "Brasil", "Brésil", "BR", "BRA", "República Federativa do Brasil" ].each do |country|
      it "retries without #{country} when the first search has no results" do
        query = "Avenida Paulista, São Paulo, #{country}"
        fallback_query = "avenida paulista, são paulo"
        json_headers = { "Content-Type" => "application/json" }

        stub_request(:get, search_url)
          .with(query: hash_including("q" => query.downcase))
          .to_return(status: 200, body: [].to_json, headers: json_headers)
        stub_request(:get, search_url)
          .with(query: hash_including("q" => fallback_query))
          .to_return(status: 200, body: [ result ].to_json, headers: json_headers)

        address = described_class.new.resolve(query)

        expect(address).to have_attributes(zip_code: "32114", city: "Daytona Beach")
        expect(
          a_request(:get, search_url).with(query: hash_including("q" => fallback_query))
        ).to have_been_made.once
      end
    end

    it "returns nil when the fallback search also has no results" do
      stub_search([])

      expect(described_class.new.resolve(query)).to be_nil
      expect(a_request(:get, search_url)).to have_been_made.twice
    end

    it "does not retry when removing the country leaves a blank query" do
      stub_search([])

      expect(described_class.new.resolve("United States")).to be_nil
      expect(a_request(:get, search_url)).to have_been_made.once
    end

    it "caches successful lookups" do
      stub_search
      resolver = described_class.new

      first = resolver.resolve(query)
      second = resolver.resolve(messy_query)

      expect(first).to have_attributes(zip_code: "32114")
      expect(second).to have_attributes(zip_code: "32114")
      expect(a_request(:get, search_url)).to have_been_made.once
    end

    it "expires cached lookups after the configured TTL" do
      stub_search
      resolver = described_class.new(
        cache: ActiveSupport::Cache::MemoryStore.new,
        cache_ttl: 30.days
      )

      resolver.resolve(query)

      travel(30.days - 1.minute) do
        resolver.resolve(query)
        expect(a_request(:get, search_url)).to have_been_made.once
      end

      travel(31.days) do
        resolver.resolve(query)
        expect(a_request(:get, search_url)).to have_been_made.twice
      end
    end

    it "does not cache empty results" do
      stub_search([])
      resolver = described_class.new

      expect(resolver.resolve("No such place")).to be_nil
      expect(resolver.resolve("No such place")).to be_nil
      expect(a_request(:get, search_url)).to have_been_made.twice
    end

    it "protects the address cache against stampedes" do
      cache = ActiveSupport::Cache::MemoryStore.new
      resolver = described_class.new(cache: cache, race_condition_ttl: 7.seconds)

      expect(cache).to receive(:fetch).with(
        anything,
        hash_including(
          expires_in: 30.days,
          race_condition_ttl: 7.seconds,
          skip_nil: true
        )
      ).and_call_original

      stub_search
      resolver.resolve(query)
    end

    it "returns nil for a blank query without making a request" do
      resolver = described_class.new

      expect(resolver.resolve("   ")).to be_nil
      expect(a_request(:get, search_url)).not_to have_been_made
    end

    it "returns nil when the result has no coordinates" do
      stub_search([ { "address" => { "city" => "Nowhere" } } ])

      expect(described_class.new.resolve("Nowhere")).to be_nil
    end

    it "falls back through the available locality fields" do
      stub_search([ {
        "lat" => "1.5",
        "lon" => "2.5",
        "address" => {
          "country_code" => "de",
          "town" => "Example Town",
          "county" => "Example County"
        }
      } ])

      address = described_class.new.resolve("Example")

      expect(address).to have_attributes(
        city: "Example Town",
        region_state: "Example County",
        country_code: "DE"
      )
    end
  end

  describe "rate limiting" do
    it "waits before making a request within the rate limit interval" do
      stub_search
      resolver = described_class.new(rate_limit_interval: 1.0)
      allow(resolver).to receive(:monotonic_now).and_return(100.25)
      described_class.last_request_at = 100.0

      expect(resolver).to receive(:sleep).with(0.75)

      resolver.resolve(query)
    end

    it "does not sleep for the first request" do
      stub_search
      resolver = described_class.new(rate_limit_interval: 1.0)
      allow(resolver).to receive(:monotonic_now).and_return(100.25)

      expect(resolver).not_to receive(:sleep)

      resolver.resolve(query)
      expect(described_class.last_request_at).to eq(100.25)
    end

    it "records the request time even when the request fails" do
      stub_search(status: 503)
      resolver = described_class.new(rate_limit_interval: 1.0)
      allow(resolver).to receive(:monotonic_now).and_return(200.0)

      expect { resolver.resolve(query) }
        .to raise_error(AddressResolver::Error)
      expect(described_class.last_request_at).to eq(200.0)
    end
  end

  describe "error handling" do
    it "raises an error for a non-success response" do
      stub_search(status: 503)

      expect { described_class.new.resolve(query) }
        .to raise_error(AddressResolver::Error, /Nominatim request failed with 503/)
    end

    it "raises an error for invalid JSON" do
      stub_request(:get, search_url).to_return(status: 200, body: "{not-json")

      expect { described_class.new.resolve(query) }
        .to raise_error(AddressResolver::Error, /Nominatim returned invalid JSON/)
    end

    it "raises an error when the request times out" do
      stub_request(:get, search_url).to_timeout

      expect { described_class.new.resolve(query) }
        .to raise_error(AddressResolver::Error, /Nominatim request failed/)
    end

    it "returns nil when the response is not an array" do
      stub_search({ "unexpected" => true })

      expect(described_class.new.resolve(query)).to be_nil
    end
  end

  describe "configuration" do
    it "does not use a placeholder contact address in the default User-Agent" do
      expect(described_class::DEFAULT_USER_AGENT).not_to include("example.com")
    end

    it "uses a custom base URL" do
      custom_url = %r{\Ahttps://nominatim.example.test/search\?}
      stub_request(:get, custom_url).to_return(status: 200, body: [ result ].to_json)

      described_class.new(base_url: "https://nominatim.example.test/").resolve(
        query
      )

      expect(a_request(:get, custom_url)).to have_been_made.once
    end
  end

  describe "HTTP clients" do
    it "uses a get_json client when available" do
      client = double("HttpClient")
      allow(client).to receive(:get_json).and_return([ result ])

      address = described_class.new(http_client: client)
                                 .resolve(query)

      expect(address.zip_code).to eq("32114")
      expect(client).to have_received(:get_json).with(search_url, headers: hash_including("Accept"))
    end

    it "uses a get client when get_json is unavailable" do
      client = double("HttpClient")
      allow(client).to receive(:get).and_return([ result ])

      address = described_class.new(http_client: client)
                                 .resolve(query)

      expect(address.zip_code).to eq("32114")
      expect(client).to have_received(:get).with(search_url, headers: hash_including("Accept"))
    end
  end

  describe "#reset_rate_limit!" do
    it "clears the class rate limit and returns self" do
      described_class.last_request_at = 123.0
      resolver = described_class.new

      expect(resolver.reset_rate_limit!).to be(resolver)
      expect(described_class.last_request_at).to be_nil
    end
  end

  it "returns nil when a coordinate is not numeric" do
    stub_search([ {
      "lat" => "north",
      "lon" => "east",
      "address" => { "city" => "Nowhere" }
    } ])

    expect(described_class.new.resolve("Nowhere")).to be_nil
  end
end
