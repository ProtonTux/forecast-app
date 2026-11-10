require "uri"

module AddressResolution
  # OpenStreetMap Nominatim adapter.
  #
  # Nominatim's public service usage requirements are enforced here:
  #   * a descriptive User-Agent identifies this application,
  #   * requests are globally throttled to at most one per second,
  #   * successful lookups are cached by AddressResolver.
  #
  # Only fully typed addresses are sent to the /search endpoint. Autocomplete is
  # deliberately not implemented.
  class Nominatim < Base
    DISPLAY_NAME = "Nominatim"
    DEFAULT_BASE_URL = "https://nominatim.openstreetmap.org"
    DEFAULT_RATE_LIMIT_INTERVAL = 1.0
    SEARCH_PATH = "/search"
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

    def initialize(base_url: nil, user_agent: nil, http_client: nil, rate_limit_interval: nil)
      config = weather_config
      super(
        base_url: base_url.presence || config&.nominatim_url.presence || DEFAULT_BASE_URL,
        user_agent: user_agent.presence || config&.nominatim_user_agent.presence,
        http_client: http_client,
        rate_limit_interval: rate_limit_interval || DEFAULT_RATE_LIMIT_INTERVAL
      )
    end

    def resolve(query)
      payload = fetch_result(query)
      return nil unless payload.is_a?(Hash)

      data = payload["address"].is_a?(Hash) ? payload["address"] : {}

      build_address(
        zip_code: data["postcode"],
        country_code: data["country_code"]&.upcase,
        city: data["city"] || data["town"] || data["village"] || data["municipality"] || data["hamlet"],
        region_state: data["state"] || data["region"] || data["county"],
        latitude: numeric(payload["lat"]),
        longitude: numeric(payload["lon"]),
        timezone: payload["timezone"]
      )
    end

    private

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

      throttle { get_json(uri.to_s, headers: request_headers) }
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

    def request_headers
      {
        "User-Agent" => user_agent,
        "Accept" => "application/json",
        "Accept-Language" => "en"
      }
    end
  end
end
