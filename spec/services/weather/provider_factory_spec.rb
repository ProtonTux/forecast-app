require "rails_helper"

RSpec.describe Weather::ProviderFactory do
  describe "#build" do
    it "builds the configured provider strategies" do
      factory = described_class.new(providers: %w[noaa open-meteo])

      expect(factory.provider_names).to eq(%w[noaa open_meteo])
      expect(factory.build.map(&:class)).to eq(
        [ Weather::Providers::Noaa, Weather::Providers::OpenMeteo ]
      )
    end

    it "uses the default provider configuration" do
      expect(described_class.new.provider_names).to eq(%w[noaa open_meteo])
    end

    it "normalizes aliases, comma-separated values, and duplicates" do
      factory = described_class.new(providers: [ "NWS, open-meteo", "openmeteo", " noaa " ])

      expect(factory.provider_names).to eq(%w[noaa open_meteo])
    end

    it "passes shared options to each provider" do
      client = instance_double("HttpClient")
      user_agent = "ForecastApp/1.0 (test)"

      providers = described_class.new(
        providers: %w[noaa open_meteo],
        http_client: client,
        user_agent: user_agent
      ).build

      expect(providers).to all(have_attributes(http_client: client, user_agent: user_agent))
    end

    it "raises for an unknown provider" do
      expect { described_class.new(providers: [ "unknown" ]).build }
        .to raise_error(Weather::ProviderFactory::UnknownProviderError, /Unknown weather provider/)
    end
  end

  describe ".build" do
    it "builds providers without instantiating the factory first" do
      providers = described_class.build(providers: [ "open_meteo" ])

      expect(providers.map(&:class)).to eq([ Weather::Providers::OpenMeteo ])
    end
  end

  describe "#call" do
    it "is an alias for build" do
      factory = described_class.new(providers: [ "noaa" ])

      expect(factory.call.map(&:class)).to eq([ Weather::Providers::Noaa ])
    end
  end
end
