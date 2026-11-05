require "digest"
require "json"
require "net/http"
require "uri"

# Resolves a free-form user address with the OpenStreetMap Nominatim API and
# returns an Address record with coordinates and postal code.
#
# Nominatim's public service usage requirements are enforced here:
#   * a descriptive User-Agent identifies this application,
#   * requests are globally throttled to at most one per second,
#   * successful lookups are cached.
#
# Only fully typed addresses are sent to the /search endpoint. Autocomplete is
# deliberately not implemented.
class AddressResolver
  class Error < StandardError; end

  DEFAULT_BASE_URL = "https://nominatim.openstreetmap.org"
  DEFAULT_USER_AGENT = "ForecastApp/1.0 (weather forecast application)"
  DEFAULT_CACHE_TTL = 30.days
  RATE_LIMIT_INTERVAL = 1.0
  SEARCH_PATH = "/search"
  CACHE_PREFIX = "address_resolver:nominatim:v1"
  COUNTRY_ALIASES = [
    "united states of america",
    "united states",
    "usa",
    "u.s.a.",
    "u.s.",
    "america",
    "federative republic of brazil",
    "república federativa do brasil",
    "brazil",
    "brasil",
    "brésil",
    "brasilien",
    "brasile",
    "bra",
    "br"
  ].freeze
  COUNTRY_NAMES = /(?<!\w)(?:#{Regexp.union(COUNTRY_ALIASES).source})(?![\w-])/i

  class << self
    def rate_limit_mutex
      @rate_limit_mutex ||= Mutex.new
    end

    def last_request_at
      @last_request_at
    end

    def last_request_at=(value)
      @last_request_at = value
    end

    def reset_rate_limit!
      @last_request_at = nil
    end
  end

  attr_reader :base_url, :user_agent, :cache, :cache_ttl, :http_client, :rate_limit_interval

  def initialize(
    base_url: nil,
    user_agent: nil,
    cache: nil,
    cache_ttl: nil,
    http_client: nil,
    rate_limit_interval: RATE_LIMIT_INTERVAL
  )
    config = weather_config
    @base_url = (base_url.presence || config&.nominatim_url.presence || DEFAULT_BASE_URL).to_s.sub(%r{/+\z}, "")
    @user_agent = user_agent.presence || config&.nominatim_user_agent.presence || DEFAULT_USER_AGENT
    @cache = cache || Rails.cache
    @cache_ttl = cache_ttl || config&.nominatim_cache_ttl || DEFAULT_CACHE_TTL
    @http_client = http_client
    @rate_limit_interval = rate_limit_interval.to_f
  end

  # Returns an Address, or nil when Nominatim has no match. Successful
  # lookups are cached so repeated searches do not hit the public endpoint.
  def resolve(query, persist: true)
    normalized_query = normalize_query(query)
    return nil if normalized_query.empty?

    key = cache_key(normalized_query)
    result = cache.read(key)

    if result.blank?
      result = fetch_result(normalized_query)
      cache.write(key, result, expires_in: cache_ttl) if result.present?
    end

    return nil if result.blank?

    address = build_address(result)
    persist_address(address) if persist && address
    address
  end
  alias call resolve

  def reset_rate_limit!
    self.class.reset_rate_limit!
    self
  end

  private

  def weather_config
    return unless defined?(Rails) && Rails.respond_to?(:application) && Rails.application

    Rails.application.config.x.weather
  end

  def normalize_query(query)
    query.to_s.strip.downcase.gsub(/\s+/, " ")
  end

  def cache_key(query)
    "#{CACHE_PREFIX}:#{Digest::SHA256.hexdigest(query)}"
  end

  def fetch_result(query)
    payload = search(query)

    if payload.blank? && (fallback_query = query_without_country(query))
      payload = search(fallback_query)
    end

    return nil unless payload.is_a?(Array)

    payload.first
  end

  def search(query)
    uri = URI.parse("#{base_url}#{SEARCH_PATH}")
    uri.query = URI.encode_www_form(
      q: query,
      format: "jsonv2",
      addressdetails: 1,
      limit: 1
    )

    throttle { request_json(uri.to_s) }
  end

  def query_without_country(query)
    stripped = query.gsub(COUNTRY_NAMES, " ")
                    .split(",")
                    .map(&:strip)
                    .reject(&:empty?)
                    .join(", ")
                    .gsub(/\s+/, " ")

    stripped if stripped.present? && stripped != query
  end

  def request_json(url)
    if http_client.respond_to?(:get_json)
      http_client.get_json(url, headers: request_headers)
    elsif http_client.respond_to?(:get)
      http_client.get(url, headers: request_headers)
    else
      default_request_json(url)
    end
  end

  def default_request_json(url)
    uri = URI.parse(url)
    request = Net::HTTP::Get.new(uri)
    request_headers.each { |key, value| request[key] = value }

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: 5,
      read_timeout: 10
    ) do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "Nominatim request failed with #{response.code} #{response.message}"
    end

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise Error, "Nominatim returned invalid JSON: #{e.message}"
  rescue Timeout::Error, SocketError, SystemCallError => e
    raise Error, "Nominatim request failed: #{e.message}"
  end

  def request_headers
    {
      "User-Agent" => user_agent,
      "Accept" => "application/json",
      "Accept-Language" => "en"
    }
  end

  # The public Nominatim service allows at most one request per second. The
  # mutex makes the limit global for this application process.
  def throttle
    self.class.rate_limit_mutex.synchronize do
      now = monotonic_now
      last_request = self.class.last_request_at

      if last_request
        wait = rate_limit_interval - (now - last_request)
        sleep(wait) if wait.positive?
      end

      begin
        yield
      ensure
        self.class.last_request_at = monotonic_now
      end
    end
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def build_address(result)
    data = result["address"].is_a?(Hash) ? result["address"] : {}
    latitude = numeric(result["lat"])
    longitude = numeric(result["lon"])
    return nil if latitude.nil? || longitude.nil?

    attributes = {
      zip_code: data["postcode"],
      country_code: data["country_code"]&.upcase,
      city: data["city"] || data["town"] || data["village"] || data["municipality"] || data["hamlet"],
      region_state: data["state"] || data["region"] || data["county"],
      latitude: latitude,
      longitude: longitude,
      timezone: result["timezone"],
      geocoding_source: "nominatim",
      geocoded_at: Time.current
    }.compact

    address = Address.find_or_initialize_by(latitude: latitude, longitude: longitude)
    address.assign_attributes(attributes)
    address
  end

  def persist_address(address)
    return address unless defined?(Address) && address.is_a?(Address)

    address.save! if address.new_record? || address.changed?
    address
  end

  def numeric(value)
    return nil if value.nil? || value == ""

    Float(value)
  rescue ArgumentError, TypeError
    nil
  end
end
