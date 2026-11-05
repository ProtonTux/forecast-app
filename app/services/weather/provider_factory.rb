module Weather
  # Creates the configured weather provider strategies. The rest of the
  # application only depends on the common provider interface, so providers
  # can be added, removed, or swapped through configuration.
  class ProviderFactory
    class UnknownProviderError < StandardError; end

    DEFAULT_PROVIDERS = %w[noaa open_meteo].freeze

    PROVIDER_CLASSES = {
      "noaa" => "Weather::Providers::Noaa",
      "open_meteo" => "Weather::Providers::OpenMeteo"
    }.freeze

    ALIASES = {
      "nws" => "noaa",
      "noaa" => "noaa",
      "open-meteo" => "open_meteo",
      "openmeteo" => "open_meteo",
      "open_meteo" => "open_meteo"
    }.freeze

    def self.build(providers: nil, **options)
      new(providers: providers, **options).build
    end

    attr_reader :provider_names, :options

    def initialize(providers: nil, **options)
      configured = providers.nil? ? self.class.configured_providers : providers
      @provider_names = self.class.normalize_names(configured)
      @options = options
    end

    def build
      provider_names.map { |name| build_provider(name) }
    end
    alias call build

    def build_provider(name)
      key = self.class.normalize_name(name)
      class_name = PROVIDER_CLASSES[key]

      unless class_name
        raise UnknownProviderError, "Unknown weather provider: #{name}"
      end

      class_name.constantize.new(**options)
    end

    def self.configured_providers
      app = defined?(Rails) && Rails.respond_to?(:application) && Rails.application
      configured = app ? Rails.application.config.x.weather&.providers : nil

      configured.present? ? configured : DEFAULT_PROVIDERS
    end

    def self.normalize_names(providers)
      Array(providers)
        .flat_map { |provider| provider.to_s.split(",") }
        .map { |provider| normalize_name(provider) }
        .reject(&:empty?)
        .uniq
    end

    def self.normalize_name(name)
      value = name.to_s.strip.downcase
      ALIASES.fetch(value, value)
    end
  end
end
