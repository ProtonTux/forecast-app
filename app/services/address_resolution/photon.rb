require "uri"

module AddressResolution
  # Photon adapter. Photon is an open-source OpenStreetMap geocoder from
  # komoot. The public demo instance is suitable for light use; configure
  # PHOTON_URL to point at a self-hosted instance for higher traffic.
  class Photon < Base
    DISPLAY_NAME = "Photon"
    DEFAULT_BASE_URL = "https://photon.komoot.io"
    DEFAULT_RATE_LIMIT_INTERVAL = 1.0
    SEARCH_PATH = "/api"

    def initialize(base_url: nil, user_agent: nil, http_client: nil, rate_limit_interval: nil)
      config = weather_config
      super(
        base_url: base_url.presence || config&.photon_url.presence || DEFAULT_BASE_URL,
        user_agent: user_agent.presence || config&.photon_user_agent.presence,
        http_client: http_client,
        rate_limit_interval: rate_limit_interval || DEFAULT_RATE_LIMIT_INTERVAL
      )
    end

    def resolve(query)
      payload = throttle { get_json(search_url(query), headers: request_headers) }
      feature = payload.is_a?(Hash) && payload["features"].is_a?(Array) ? payload["features"].first : nil
      return nil unless feature.is_a?(Hash)

      properties = feature["properties"].is_a?(Hash) ? feature["properties"] : {}
      coordinates = feature.dig("geometry", "coordinates")
      coordinates = [] unless coordinates.is_a?(Array)

      build_address(
        zip_code: properties["postcode"],
        country_code: properties["countrycode"]&.upcase,
        city: properties["city"] || properties["town"] || properties["village"] ||
              properties["locality"] || properties["district"] || properties["name"],
        region_state: properties["state"] || properties["county"],
        latitude: numeric(coordinates[1]),
        longitude: numeric(coordinates[0]),
        timezone: nil
      )
    end

    private

    def search_url(query)
      uri = URI.parse("#{base_url}#{SEARCH_PATH}")
      uri.query = URI.encode_www_form(q: query, limit: 1, lang: "en")
      uri.to_s
    end

    def request_headers
      { "Accept" => "application/json" }
    end
  end
end
