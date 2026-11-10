require "json"
require "net/http"
require "uri"

module AddressResolution
  # Shared behaviour for geocoding providers: HTTP handling, provider-scoped
  # rate limiting, and conversion into the common ResolvedAddress value object.
  # Subclasses only build provider-specific requests and map their responses.
  class Base
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    DEFAULT_USER_AGENT = "ForecastApp/1.0 (weather forecast application)"
    DEFAULT_RATE_LIMIT_INTERVAL = 1.0

    class << self
      def provider_key
        name.demodulize.underscore
      end

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

    attr_reader :base_url, :user_agent, :http_client, :rate_limit_interval

    def initialize(base_url:, user_agent: nil, http_client: nil, rate_limit_interval: nil)
      @base_url = base_url.to_s.sub(%r{/+\z}, "")
      @user_agent = user_agent.presence || configured_user_agent
      @http_client = http_client
      @rate_limit_interval = (rate_limit_interval || self.class::DEFAULT_RATE_LIMIT_INTERVAL).to_f
    end

    def provider_key
      self.class.provider_key
    end

    # Returns a ResolvedAddress, or nil when the provider has no match.
    def resolve(_query)
      raise NotImplementedError, "#{self.class} must implement #resolve"
    end

    def reset_rate_limit!
      self.class.reset_rate_limit!
      self
    end

    private

    def weather_config
      return unless defined?(Rails) && Rails.respond_to?(:application) && Rails.application

      Rails.application.config.x.weather
    end

    def configured_user_agent
      weather_config&.user_agent.presence || DEFAULT_USER_AGENT
    end

    def get_json(url, headers: {})
      if http_client.respond_to?(:get_json)
        http_client.get_json(url, headers: headers)
      elsif http_client.respond_to?(:get)
        http_client.get(url, headers: headers)
      else
        default_get_json(url, headers: headers)
      end
    end

    def default_get_json(url, headers: {})
      uri = URI.parse(url)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = user_agent
      request["Accept"] = "application/json"
      headers.each { |key, value| request[key] = value }

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "#{display_name} request failed with #{response.code} #{response.message}"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "#{display_name} returned invalid JSON: #{e.message}"
    rescue Timeout::Error, SocketError, SystemCallError => e
      raise Error, "#{display_name} request failed: #{e.message}"
    end

    def display_name
      self.class::DISPLAY_NAME
    end

    # The public endpoints have different fair-use limits. The mutex and
    # monotonic clock make each provider's limit process-wide and immune to
    # wall-clock changes.
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

    def numeric(value)
      return nil if value.nil? || value == ""

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def build_address(latitude:, longitude:, zip_code: nil, country_code: nil,
                      city: nil, region_state: nil, timezone: nil)
      return nil if latitude.nil? || longitude.nil?

      ResolvedAddress.new(
        zip_code: zip_code,
        country_code: country_code,
        city: city,
        region_state: region_state,
        latitude: latitude,
        longitude: longitude,
        timezone: timezone,
        geocoding_source: provider_key,
        geocoded_at: Time.current
      )
    end
  end
end
