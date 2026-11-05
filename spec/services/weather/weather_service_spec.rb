require "rails_helper"

RSpec.describe Weather::WeatherService do
  class FakeProvider
    attr_reader :name, :calls

    def initialize(name, result: nil, error: nil)
      @name = name
      @result = result
      @error = error
      @calls = 0
    end

    def forecast(latitude:, longitude:)
      @calls += 1
      raise @error if @error

      @result
    end
  end

  class FakeFactory
    attr_reader :providers, :build_count

    def initialize(providers)
      @providers = providers
      @build_count = 0
    end

    def build
      @build_count += 1
      providers
    end

    def provider_names
      providers.map(&:name)
    end
  end

  let(:alpha) do
    FakeProvider.new(
      "alpha",
      result: {
        source: "alpha",
        location: { timezone: "UTC", city: "Alpha" },
        current: { temperature_c: 10.0, wind_speed_ms: 2.0, weather_code: 3 },
        hourly: [
          { time: "2026-11-03T12:00:00Z", temperature_c: 10.0 },
          { time: "2026-11-03T13:00:00Z", temperature_c: 11.0 }
        ],
        daily: [ { date: "2026-11-03", high_c: 12.0, weather_code: 3 } ]
      }
    )
  end

  let(:beta) do
    FakeProvider.new(
      "beta",
      result: {
        source: "beta",
        location: { timezone: "UTC", city: "Beta" },
        current: { temperature_c: 14.0, humidity: 50.0, weather_code: 61 },
        hourly: [
          { time: "2026-11-03T12:00:00Z", temperature_c: 14.0 },
          { time: "2026-11-03T13:00:00Z", temperature_c: 13.0 }
        ],
        daily: [ { date: "2026-11-03", high_c: 16.0, weather_code: 61 } ]
      }
    )
  end

  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:address_query) do
    "1801 West International Speedway Blvd, Daytona Beach, Florida, United States 32114"
  end

  def build_service(providers: [ alpha, beta ], factory: nil, address_resolver: nil)
    described_class.new(
      address_resolver: address_resolver,
      provider_factory: factory || FakeFactory.new(providers),
      cache: cache
    )
  end

  describe "#forecast_for" do
    it "combines provider results into the common weather format" do
      result = build_service.forecast_for(latitude: 10, longitude: 20)

      expect(result[:sources]).to eq(%w[alpha beta])
      expect(result[:location]).to include(latitude: 10.0, longitude: 20.0, city: "Beta")
      expect(result[:current]).to include(
        temperature_c: 12.0,
        wind_speed_ms: 2.0,
        humidity: 50.0,
        weather_code: 3
      )
      expect(result[:hourly].length).to eq(2)
      expect(result[:hourly].map { |entry| entry[:temperature_c] }).to eq([ 12.0, 12.0 ])
      expect(result[:daily].first).to include(high_c: 14.0, weather_code: 3)
      expect(result[:provider_errors]).to be_nil
      expect(Time.iso8601(result[:generated_at])).to be_within(5.seconds).of(Time.current)
    end

    it "normalizes provider results with string keys" do
      string_keyed = FakeProvider.new(
        "gamma",
        result: {
          "source" => "gamma",
          "location" => { "timezone" => "UTC" },
          "current" => { "temperature_c" => 7.5, "weather_code" => 0 }
        }
      )

      result = build_service(providers: [ string_keyed ]).forecast_for(latitude: 1, longitude: 2)

      expect(result[:sources]).to eq([ "gamma" ])
      expect(result[:current]).to include(temperature_c: 7.5, weather_code: 0)
    end

    it "includes address metadata when an address is supplied" do
      address = instance_double(
        Address,
        latitude: 29.1858,
        longitude: -81.0700,
        zip_code: "32114",
        city: "Daytona Beach",
        region_state: "Florida",
        country_code: "US",
        timezone: "America/New_York"
      )

      result = build_service.forecast_for(address)

      expect(result[:location]).to include(
        latitude: 29.1858,
        longitude: -81.0700,
        postal_code: "32114",
        city: "Daytona Beach",
        region: "Florida",
        country: "US",
        timezone: "America/New_York"
      )
    end

    it "accepts a hash with string coordinate keys" do
      result = build_service.forecast_for({ "latitude" => 4, "longitude" => 5 })

      expect(result[:location]).to include(latitude: 4.0, longitude: 5.0)
    end

    it "rejects out-of-range coordinates" do
      expect { build_service.forecast_for(latitude: 91, longitude: 0) }
        .to raise_error(ArgumentError, /Invalid latitude/)
      expect { build_service.forecast_for(latitude: 0, longitude: 181) }
        .to raise_error(ArgumentError, /Invalid longitude/)
    end

    it "rejects missing coordinates" do
      expect { build_service.forecast_for }
        .to raise_error(ArgumentError, /Invalid latitude/)
    end
  end

  describe "caching" do
    it "returns a cached forecast without calling the providers again" do
      service = build_service
      factory = service.provider_factory

      first = service.forecast_for(latitude: 10, longitude: 20)
      result = service.forecast_for(latitude: 10, longitude: 20)

      expect(first[:cache_hit]).to be(false)
      expect(result[:cache_hit]).to be(true)
      expect(factory.build_count).to eq(1)
      expect(alpha.calls).to eq(1)
      expect(beta.calls).to eq(1)
      expect(cache.exist?("weather:forecast:v1:10.0000:20.0000:alpha,beta")).to be(true)
      expect(result[:sources]).to eq(%w[alpha beta])
    end

    it "caches by rounded coordinates and configured providers" do
      build_service.forecast_for(latitude: 10.00004, longitude: 20.00004)

      expect(cache.exist?("weather:forecast:v1:10.0000:20.0000:alpha,beta")).to be(true)
    end

    it "defaults to a 30 minute forecast cache TTL" do
      expect(build_service.cache_ttl).to eq(30.minutes)
    end

    it "expires the forecast after the cache TTL" do
      service = build_service
      factory = service.provider_factory

      service.forecast_for(latitude: 10, longitude: 20)

      travel 29.minutes do
        service.forecast_for(latitude: 10, longitude: 20)
        expect(factory.build_count).to eq(1)
      end

      travel 31.minutes do
        service.forecast_for(latitude: 10, longitude: 20)
        expect(factory.build_count).to eq(2)
      end
    end

    it "uses a configured cache TTL" do
      service = described_class.new(
        address_resolver: nil,
        provider_factory: FakeFactory.new([ alpha ]),
        cache: cache,
        cache_ttl: 1.minute
      )

      service.forecast_for(latitude: 10, longitude: 20)

      travel 61.seconds do
        service.forecast_for(latitude: 10, longitude: 20)
        expect(service.provider_factory.build_count).to eq(2)
      end
    end
  end

  describe "provider failures" do
    it "uses the remaining providers and records the failure when one provider fails" do
      failing = FakeProvider.new("failing", error: StandardError.new("provider unavailable"))

      result = build_service(providers: [ failing, alpha ]).forecast_for(latitude: 10, longitude: 20)

      expect(result[:sources]).to eq([ "alpha" ])
      expect(result[:provider_errors]).to eq(
        "failing" => "StandardError: provider unavailable"
      )
      expect(failing.calls).to eq(1)
    end

    it "records a provider that returns no data" do
      empty = FakeProvider.new("empty", result: nil)

      result = build_service(providers: [ empty, alpha ]).forecast_for(latitude: 10, longitude: 20)

      expect(result[:sources]).to eq([ "alpha" ])
      expect(result[:provider_errors]).to eq("empty" => "Provider returned no data")
    end

    it "raises when every provider fails" do
      first = FakeProvider.new("first", error: StandardError.new("down"))
      second = FakeProvider.new("second", error: RuntimeError.new("timeout"))

      expect { build_service(providers: [ first, second ]).forecast_for(latitude: 10, longitude: 20) }
        .to raise_error(Weather::WeatherService::AllProvidersFailedError) { |error|
          expect(error.message).to include("first (StandardError: down)")
          expect(error.message).to include("second (RuntimeError: timeout)")
        }
    end

    it "raises when no providers are configured" do
      expect { build_service(providers: []).forecast_for(latitude: 10, longitude: 20) }
        .to raise_error(Weather::WeatherService::AllProvidersFailedError, /No weather providers are configured/)
    end
  end

  describe "#forecast" do
    it "resolves a free-form address before requesting the forecast" do
      resolver = instance_double(AddressResolver)
      address = instance_double(
        Address,
        latitude: 29.1858,
        longitude: -81.0700,
        zip_code: "32114",
        city: "Daytona Beach",
        region_state: "FL",
        country_code: "US",
        timezone: "America/New_York"
      )
      allow(resolver).to receive(:resolve).with(address_query).and_return(address)

      result = build_service(address_resolver: resolver).forecast(address_query)

      expect(result[:location]).to include(city: "Daytona Beach", postal_code: "32114")
      expect(resolver).to have_received(:resolve).with(address_query)
    end

    it "resolves an Address passed directly" do
      resolver = instance_double(AddressResolver)
      allow(resolver).to receive(:resolve)
      address = instance_double(
        Address,
        latitude: 1.0,
        longitude: 2.0,
        zip_code: nil,
        city: "Example",
        region_state: nil,
        country_code: "US",
        timezone: "UTC"
      )

      result = build_service(address_resolver: resolver).forecast(address)

      expect(result[:location]).to include(city: "Example", country: "US")
      expect(resolver).not_to have_received(:resolve)
    end

    it "bypasses address resolution when coordinates are provided" do
      resolver = instance_double(AddressResolver)
      allow(resolver).to receive(:resolve)

      result = build_service(address_resolver: resolver).forecast(latitude: 10, longitude: 20)

      expect(result[:location]).to include(latitude: 10.0, longitude: 20.0)
      expect(resolver).not_to have_received(:resolve)
    end

    it "raises when the address cannot be resolved" do
      resolver = instance_double(AddressResolver, resolve: nil)

      expect { build_with_resolver(resolver).forecast("Nowhere") }
        .to raise_error(Weather::WeatherService::AddressNotFoundError)
    end

    it "raises for a nil input" do
      expect { build_service.forecast(nil) }
        .to raise_error(Weather::WeatherService::AddressNotFoundError)
    end

    it "resolves non-coordinate input as an address string" do
      resolver = instance_double(AddressResolver, resolve: nil)

      expect { build_service(address_resolver: resolver).forecast(12_345) }
        .to raise_error(Weather::WeatherService::AddressNotFoundError)
      expect(resolver).to have_received(:resolve).with("12345")
    end
  end

  describe "#fetch" do
    it "fetches a forecast for the supplied coordinates" do
      result = build_service.fetch(latitude: 10, longitude: 20)

      expect(result[:location]).to include(latitude: 10.0, longitude: 20.0)
    end
  end

  describe ".forecast" do
    it "builds a service and delegates the forecast" do
      service = instance_double(described_class)
      allow(described_class).to receive(:new).and_return(service)
      allow(service).to receive(:forecast).with(address_query, latitude: nil, longitude: nil)
                                        .and_return(:forecast)

      expect(described_class.forecast(address_query)).to eq(:forecast)
    end
  end

  describe "coordinate edge cases" do
    it "accepts a hash with symbol coordinate keys" do
      result = build_service.forecast_for({ latitude: 6, longitude: 7 })

      expect(result[:location]).to include(latitude: 6.0, longitude: 7.0)
    end

    it "treats non-numeric coordinates as missing" do
      expect { build_service.forecast_for({ latitude: "north" }) }
        .to raise_error(ArgumentError, /Invalid latitude/)
    end
  end

  describe "cache keys" do
    it "derives provider names when the factory does not expose them" do
      factory = double("ProviderFactory")
      allow(factory).to receive(:build).and_return([ alpha ])
      service = described_class.new(address_resolver: nil, provider_factory: factory, cache: cache)

      service.forecast_for(latitude: 10, longitude: 20)

      expect(cache.exist?("weather:forecast:v1:10.0000:20.0000:alpha")).to be(true)
    end
  end

  def build_with_resolver(resolver)
    described_class.new(
      address_resolver: resolver,
      provider_factory: FakeFactory.new([ alpha ]),
      cache: cache
    )
  end
end
