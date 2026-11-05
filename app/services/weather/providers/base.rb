require "json"
require "net/http"
require "uri"

module Weather
  module Providers
    class Error < StandardError; end

    # Common interface implemented by every weather provider adapter. A
    # provider fetches its raw upstream response and delegates conversion to
    # Weather::Normalizer, so callers only ever see the common weather format.
    class Base
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 15

      attr_reader :http_client, :normalizer, :user_agent

      def initialize(http_client: nil, normalizer: Weather::Normalizer.new, user_agent: nil)
        @http_client = http_client
        @normalizer = normalizer
        @user_agent = user_agent || configured_user_agent
      end

      def self.provider_name
        name.demodulize.underscore
      end

      def name
        self.class.provider_name
      end

      def configured?
        true
      end

      # Returns the common weather format for the given coordinates.
      def forecast(latitude:, longitude:)
        payload = fetch(latitude: latitude, longitude: longitude)
        normalizer.call(provider: name, payload: payload)
      end

      private

      # Provider subclasses must implement this and return their raw payload.
      def fetch(latitude:, longitude:)
        raise NotImplementedError, "#{self.class} must implement #fetch"
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
        request["Accept"] = "application/geo+json, application/json"
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
          raise Error, "#{name} request failed with #{response.code} #{response.message}"
        end

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Error, "#{name} returned invalid JSON: #{e.message}"
      rescue Timeout::Error, SocketError, SystemCallError => e
        raise Error, "#{name} request failed: #{e.message}"
      end

      def configured_user_agent
        return default_user_agent unless defined?(Rails) && Rails.respond_to?(:application) && Rails.application

        Rails.application.config.x.weather&.user_agent.presence || default_user_agent
      end

      def default_user_agent
        "ForecastApp/1.0 (weather forecast application)"
      end
    end
  end
end
