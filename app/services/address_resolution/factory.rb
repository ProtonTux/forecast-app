module AddressResolution
  # Builds the configured geocoding adapter. The rest of the application only
  # depends on AddressResolver#resolve, so providers can be swapped through
  # ADDRESS_RESOLVER without changing controllers or WeatherService.
  class Factory
    DEFAULT_RESOLVER = "nominatim"

    RESOLVERS = {
      "nominatim" => "AddressResolution::Nominatim",
      "photon" => "AddressResolution::Photon",
      "open_meteo" => "AddressResolution::OpenMeteo"
    }.freeze

    ALIASES = {
      "nominatim" => "nominatim",
      "osm" => "nominatim",
      "openstreetmap" => "nominatim",
      "open_street_map" => "nominatim",
      "photon" => "photon",
      "komoot" => "photon",
      "open_meteo" => "open_meteo",
      "open-meteo" => "open_meteo",
      "openmeteo" => "open_meteo",
      "geocoding" => "open_meteo"
    }.freeze

    attr_reader :resolver_name, :options

    def self.build(resolver: nil, **options)
      new(resolver: resolver, **options).build
    end

    def initialize(resolver: nil, **options)
      configured = resolver.nil? ? self.class.configured_resolver : resolver
      @resolver_name = self.class.normalize_name(configured)
      @options = options
    end

    def build
      key = self.class.validate!(resolver_name)
      RESOLVERS.fetch(key).constantize.new(**options)
    end
    alias call build

    def self.configured_resolver
      app = defined?(Rails) && Rails.respond_to?(:application) && Rails.application
      configured = app ? Rails.application.config.x.weather&.address_resolver : nil

      configured.presence || DEFAULT_RESOLVER
    end

    def self.normalize_name(name)
      value = name.to_s.strip.downcase
      ALIASES.fetch(value, value)
    end

    def self.validate!(name)
      key = normalize_name(name)

      unless RESOLVERS.key?(key)
        raise UnknownResolverError, "Unknown address resolver: #{name}"
      end

      key
    end

    def self.reset_rate_limits!
      RESOLVERS.each_value do |class_name|
        class_name.constantize.reset_rate_limit!
      end
    end
  end
end
