require "rails_helper"

RSpec.describe AddressResolution::Factory do
  def with_configured_resolver(value)
    config = Rails.application.config.x.weather
    original = config.address_resolver
    config.address_resolver = value
    yield
  ensure
    config.address_resolver = original
  end

  describe ".build" do
    it "builds the default Nominatim resolver" do
      expect(described_class.build).to be_a(AddressResolution::Nominatim)
    end

    it "builds the explicit provider" do
      expect(described_class.build(resolver: "photon")).to be_a(AddressResolution::Photon)
    end

    it "passes adapter options through" do
      client = double("HttpClient")

      adapter = described_class.build(
        resolver: "photon",
        base_url: "https://photon.example.test/",
        http_client: client
      )

      expect(adapter.base_url).to eq("https://photon.example.test")
      expect(adapter.http_client).to be(client)
    end

    it "raises for an unknown resolver" do
      expect { described_class.build(resolver: "bogus") }
        .to raise_error(AddressResolution::UnknownResolverError, /bogus/)
    end
  end

  describe "aliases" do
    {
      "nominatim" => AddressResolution::Nominatim,
      "osm" => AddressResolution::Nominatim,
      "openstreetmap" => AddressResolution::Nominatim,
      "open_street_map" => AddressResolution::Nominatim,
      "photon" => AddressResolution::Photon,
      "komoot" => AddressResolution::Photon,
      "open_meteo" => AddressResolution::OpenMeteo,
      "open-meteo" => AddressResolution::OpenMeteo,
      "openmeteo" => AddressResolution::OpenMeteo,
      "geocoding" => AddressResolution::OpenMeteo
    }.each do |name, klass|
      it "maps #{name.inspect} to #{klass}" do
        expect(described_class.build(resolver: name)).to be_a(klass)
      end
    end

    it "normalizes case and surrounding whitespace" do
      expect(described_class.build(resolver: "  PhoTon  ")).to be_a(AddressResolution::Photon)
    end
  end

  describe ".configured_resolver" do
    it "uses the configured value" do
      with_configured_resolver("photon") do
        expect(described_class.configured_resolver).to eq("photon")
        expect(described_class.build).to be_a(AddressResolution::Photon)
      end
    end

    it "defaults to Nominatim when the configured value is blank" do
      with_configured_resolver(nil) do
        expect(described_class.configured_resolver).to eq("nominatim")
        expect(described_class.new.resolver_name).to eq("nominatim")
      end
    end

    it "defaults to Nominatim when there is no Rails application" do
      allow(Rails).to receive(:application).and_return(nil)

      expect(described_class.configured_resolver).to eq("nominatim")
    end
  end

  describe ".validate!" do
    it "returns the canonical resolver name" do
      expect(described_class.validate!("Komoot")).to eq("photon")
    end

    it "raises for an unknown resolver" do
      expect { described_class.validate!("bogus") }
        .to raise_error(AddressResolution::UnknownResolverError, "Unknown address resolver: bogus")
    end
  end

  describe "#build" do
    it "builds an instance and supports the call alias" do
      expect(described_class.new(resolver: "open_meteo").build)
        .to be_a(AddressResolution::OpenMeteo)
      expect(described_class.new(resolver: "open_meteo").call)
        .to be_a(AddressResolution::OpenMeteo)
    end

    it "raises for an unknown resolver" do
      expect { described_class.new(resolver: "bogus").build }
        .to raise_error(AddressResolution::UnknownResolverError)
    end
  end

  describe ".reset_rate_limits!" do
    it "clears every adapter rate limit" do
      AddressResolution::Nominatim.last_request_at = 1.0
      AddressResolution::Photon.last_request_at = 2.0
      AddressResolution::OpenMeteo.last_request_at = 3.0

      described_class.reset_rate_limits!

      expect(AddressResolution::Nominatim.last_request_at).to be_nil
      expect(AddressResolution::Photon.last_request_at).to be_nil
      expect(AddressResolution::OpenMeteo.last_request_at).to be_nil
    end
  end
end
