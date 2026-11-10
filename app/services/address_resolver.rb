require "digest"

# Resolves a free-form user address through the configured geocoding provider
# and returns an immutable ResolvedAddress value object with coordinates and
# postal code.
#
# The active provider is selected with ADDRESS_RESOLVER:
#   * nominatim (default)
#   * photon
#   * open_meteo
#
# Successful lookups are cached in Rails.cache for 30 days. Empty results are
# not cached, and race_condition_ttl reduces cache stampedes when popular
# entries expire.
class AddressResolver
  Error = AddressResolution::Error

  CACHE_PREFIX = "address_resolver"
  DEFAULT_CACHE_TTL = 30.days
  DEFAULT_RACE_CONDITION_TTL = 10.seconds

  attr_reader :resolver, :cache, :cache_ttl, :race_condition_ttl

  def initialize(
    provider: nil,
    cache: nil,
    cache_ttl: nil,
    race_condition_ttl: nil,
    http_client: nil,
    **resolver_options
  )
    @resolver = AddressResolution::Factory.build(
      resolver: provider,
      http_client: http_client,
      **resolver_options
    )
    @cache = cache || Rails.cache
    @cache_ttl = cache_ttl || configured_cache_ttl
    @race_condition_ttl = race_condition_ttl || configured_race_condition_ttl
  end

  # Returns a ResolvedAddress, or nil when the provider has no match.
  def resolve(query)
    normalized_query = normalize_query(query)
    return nil if normalized_query.empty?

    result = cache.fetch(
      cache_key(normalized_query),
      expires_in: cache_ttl,
      race_condition_ttl: race_condition_ttl,
      skip_nil: true
    ) do
      resolver.resolve(normalized_query)
    end

    return nil if result.blank?

    result
  end
  alias call resolve

  def reset_rate_limit!
    resolver.reset_rate_limit!
    self
  end

  def self.reset_rate_limit!
    AddressResolution::Factory.reset_rate_limits!
  end

  private

  def weather_config
    return unless defined?(Rails) && Rails.respond_to?(:application) && Rails.application

    Rails.application.config.x.weather
  end

  def configured_cache_ttl
    weather_config&.address_cache_ttl.presence || DEFAULT_CACHE_TTL
  end

  def configured_race_condition_ttl
    weather_config&.race_condition_ttl.presence || DEFAULT_RACE_CONDITION_TTL
  end

  def normalize_query(query)
    query.to_s.strip.downcase.gsub(/\s+/, " ")
  end

  def cache_key(query)
    "#{CACHE_PREFIX}:#{resolver.provider_key}:v1:#{Digest::SHA256.hexdigest(query)}"
  end
end
