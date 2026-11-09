module Weather
  # Coordinates the configured weather providers and combines their normalized
  # results. Forecast responses are stored in Rails.cache for 30 minutes and
  # are never persisted as ActiveRecord models.
  class WeatherService
    CACHE_PREFIX = "weather:forecast:v1"
    DEFAULT_CACHE_TTL = 30.minutes
    DEFAULT_RACE_CONDITION_TTL = 10.seconds

    class Error < StandardError; end
    class AddressNotFoundError < Error; end
    class AllProvidersFailedError < Error; end

    attr_reader :address_resolver, :provider_factory, :cache, :cache_ttl,
                :race_condition_ttl

    def initialize(
      address_resolver: AddressResolver.new,
      provider_factory: nil,
      providers: nil,
      cache: nil,
      cache_ttl: nil,
      race_condition_ttl: nil,
      normalizer: Weather::Normalizer.new,
      http_client: nil,
      user_agent: nil
    )
      @address_resolver = address_resolver
      @provider_factory = provider_factory || ProviderFactory.new(
        providers: providers,
        http_client: http_client,
        normalizer: normalizer,
        user_agent: user_agent
      )
      @cache = cache || Rails.cache
      @cache_ttl = cache_ttl || configured_cache_ttl
      @race_condition_ttl = race_condition_ttl || configured_race_condition_ttl
    end

    def self.forecast(input = nil, latitude: nil, longitude: nil, **options)
      new(**options).forecast(input, latitude: latitude, longitude: longitude)
    end

    # Accepts a ResolvedAddress, a free-form address String, or a Hash/object
    # with latitude and longitude. Coordinates can also be passed as keywords.
    def forecast(input = nil, latitude: nil, longitude: nil)
      if latitude.present? && longitude.present?
        return forecast_for(latitude: latitude, longitude: longitude)
      end

      address = resolve_address(input)
      raise AddressNotFoundError, "Could not resolve the supplied address" unless address

      forecast_for(address)
    end
    alias call forecast

    # Returns the combined common weather format for an address or coordinate
    # pair. The normalized response is cached in Rails.cache for 30 minutes.
    def forecast_for(address = nil, latitude: nil, longitude: nil)
      if address.is_a?(Hash) && address.key?(:latitude) && address.key?(:longitude)
        latitude ||= address[:latitude]
        longitude ||= address[:longitude]
      elsif address.is_a?(Hash) && address.key?("latitude") && address.key?("longitude")
        latitude ||= address["latitude"]
        longitude ||= address["longitude"]
      end

      latitude = coordinate(address, :latitude) if latitude.nil?
      longitude = coordinate(address, :longitude) if longitude.nil?

      latitude = normalize_coordinate(latitude, :latitude)
      longitude = normalize_coordinate(longitude, :longitude)

      key = cache_key(latitude, longitude)
      cache_hit = true
      result = cache.fetch(
        key,
        expires_in: cache_ttl,
        race_condition_ttl: race_condition_ttl
      ) do
        cache_hit = false
        build_forecast(latitude: latitude, longitude: longitude, address: address)
      end

      result.merge(cache_hit: cache_hit)
    end

    def fetch(latitude:, longitude:, address: nil)
      forecast_for(address, latitude: latitude, longitude: longitude)
    end

    private

    def configured_cache_ttl
      app = defined?(Rails) && Rails.respond_to?(:application) && Rails.application
      configured = app ? Rails.application.config.x.weather&.cache_ttl : nil

      configured.presence || DEFAULT_CACHE_TTL
    end

    def configured_race_condition_ttl
      app = defined?(Rails) && Rails.respond_to?(:application) && Rails.application
      configured = app ? Rails.application.config.x.weather&.race_condition_ttl : nil

      configured.presence || DEFAULT_RACE_CONDITION_TTL
    end

    def resolve_address(input)
      case input
      when nil
        nil
      when String
        address_resolver.resolve(input)
      else
        if coordinate(input, :latitude) && coordinate(input, :longitude)
          input
        else
          address_resolver.resolve(input.to_s)
        end
      end
    end

    def build_forecast(latitude:, longitude:, address:)
      providers = provider_factory.build
      results = []
      errors = {}

      providers.each do |provider|
        provider_name = provider_name_for(provider)

        begin
          result = provider.forecast(latitude: latitude, longitude: longitude)
          if result.present?
            results << normalize_result(result)
          else
            errors[provider_name] = "Provider returned no data"
          end
        rescue StandardError => e
          errors[provider_name] = "#{e.class}: #{e.message}"
          log_provider_failure(provider_name, e)
        end
      end

      if results.empty?
        raise AllProvidersFailedError, failure_message(errors)
      end

      combine_results(
        results,
        latitude: latitude,
        longitude: longitude,
        address: address,
        errors: errors
      )
    end

    def failure_message(errors)
      return "No weather providers are configured" if errors.empty?

      details = errors.map { |name, error| "#{name} (#{error})" }.join(", ")
      "All weather providers failed: #{details}"
    end

    def combine_results(results, latitude:, longitude:, address:, errors:)
      location = results.filter_map { |result| result[:location] }.reduce({}) do |combined, value|
        combined.merge(value)
      end

      location = location.merge(latitude: latitude, longitude: longitude)
      location = location.merge(address_location(address)) if address

      {
        location: location.compact,
        current: merge_entries(results.map { |result| result[:current] }),
        hourly: merge_series(results.flat_map { |result| Array(result[:hourly]) }, :time),
        daily: merge_series(results.flat_map { |result| Array(result[:daily]) }, :date),
        sources: results.filter_map { |result| result[:source] }.uniq,
        generated_at: Time.current.iso8601,
        provider_errors: errors.presence
      }.compact
    end

    def merge_series(entries, key)
      entries = entries.compact.select { |entry| entry.is_a?(Hash) && entry[key].present? }
      return [] if entries.empty?

      entries.group_by { |entry| entry[key] }
             .map { |_value, group| merge_entries(group) }
             .sort_by { |entry| entry[key].to_s }
    end

    def merge_entries(entries)
      entries = entries.compact
      return nil if entries.empty?

      keys = entries.flat_map(&:keys).uniq
      keys.each_with_object({}) do |key, merged|
        values = entries.filter_map { |entry| entry[key] }
        next if values.empty?

        merged[key] = merged_value(key, values)
      end
    end

    def merged_value(key, values)
      if key == :weather_code
        values.first
      elsif values.all? { |value| value.is_a?(Numeric) }
        (values.sum.to_f / values.length).round(2)
      else
        values.first
      end
    end

    def address_location(address)
      {
        postal_code: address_value(address, :zip_code),
        city: address_value(address, :city),
        region: address_value(address, :region_state),
        country: address_value(address, :country_code),
        timezone: address_value(address, :timezone)
      }.compact
    end

    def address_value(address, key)
      if address.respond_to?(key)
        address.public_send(key)
      elsif address.respond_to?(:[])
        address[key] || address[key.to_s]
      end
    end

    def coordinate(address, key)
      value = address_value(address, key)

      return nil if value.nil? || value == ""

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def normalize_coordinate(value, key)
      coordinate = Float(value)
      valid = key == :latitude ? coordinate.between?(-90, 90) : coordinate.between?(-180, 180)

      raise ArgumentError, "Invalid #{key}: #{value.inspect}" unless valid

      coordinate
    rescue ArgumentError, TypeError
      raise ArgumentError, "Invalid #{key}: #{value.inspect}"
    end

    def cache_key(latitude, longitude)
      providers = provider_names_for_cache
      format("%s:%.4f:%.4f:%s", CACHE_PREFIX, latitude, longitude, Array(providers).sort.join(","))
    end

    def provider_names_for_cache
      return provider_factory.provider_names if provider_factory.respond_to?(:provider_names)

      provider_factory.build.map { |provider| provider_name_for(provider) }
    end

    def provider_name_for(provider)
      provider.respond_to?(:name) ? provider.name : provider.class.name
    end

    def normalize_result(result)
      result.respond_to?(:deep_symbolize_keys) ? result.deep_symbolize_keys : result
    end

    def log_provider_failure(provider_name, error)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.warn("[WeatherService] #{provider_name} failed: #{error.class}: #{error.message}")
    end
  end
end
