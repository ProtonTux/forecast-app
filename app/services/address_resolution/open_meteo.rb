require "uri"

module AddressResolution
  # Open-Meteo Geocoding adapter. The service is built for city and postal-code
  # searches; full street addresses will usually return no result. The endpoint
  # is free for non-commercial use and returns GeoNames data.
  class OpenMeteo < Base
    DISPLAY_NAME = "Open-Meteo Geocoding"
    DEFAULT_BASE_URL = "https://geocoding-api.open-meteo.com"
    DEFAULT_RATE_LIMIT_INTERVAL = 0.1
    SEARCH_PATH = "/v1/search"

    def initialize(base_url: nil, user_agent: nil, http_client: nil, rate_limit_interval: nil)
      config = weather_config
      super(
        base_url: base_url.presence || config&.open_meteo_geocoding_url.presence || DEFAULT_BASE_URL,
        user_agent: user_agent.presence || config&.open_meteo_geocoding_user_agent.presence,
        http_client: http_client,
        rate_limit_interval: rate_limit_interval || DEFAULT_RATE_LIMIT_INTERVAL
      )
    end

    def resolve(query)
      payload = throttle { get_json(search_url(query), headers: request_headers) }
      result = payload.is_a?(Hash) && payload["results"].is_a?(Array) ? payload["results"].first : nil
      return nil unless result.is_a?(Hash)

      build_address(
        zip_code: Array(result["postcodes"]).first || result["postcode"],
        country_code: result["country_code"]&.upcase,
        city: result["name"],
        region_state: result["admin1"] || result["admin2"],
        latitude: numeric(result["latitude"]),
        longitude: numeric(result["longitude"]),
        timezone: result["timezone"]
      )
    end

    private

    def search_url(query)
      uri = URI.parse("#{base_url}#{SEARCH_PATH}")
      uri.query = URI.encode_www_form(name: query, count: 1, language: "en", format: "json")
      uri.to_s
    end

    def request_headers
      { "Accept" => "application/json" }
    end
  end
end
