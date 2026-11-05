require "uri"

module Weather
  module Providers
    # Adapter for the Open-Meteo API.
    #
    # Open-Meteo supports metric units directly, so the request asks for °C,
    # m/s, and mm. Visibility is returned in metres and is converted to
    # kilometres by the Normalizer.
    class OpenMeteo < Base
      BASE_URL = "https://api.open-meteo.com/v1/forecast"

      CURRENT_FIELDS = %w[
        temperature_2m
        relative_humidity_2m
        apparent_temperature
        precipitation
        weather_code
        cloud_cover
        surface_pressure
        wind_speed_10m
        wind_direction_10m
        wind_gusts_10m
        visibility
        is_day
      ].freeze

      HOURLY_FIELDS = %w[
        temperature_2m
        relative_humidity_2m
        apparent_temperature
        precipitation
        precipitation_probability
        weather_code
        cloud_cover
        surface_pressure
        wind_speed_10m
        wind_direction_10m
        wind_gusts_10m
        visibility
        is_day
      ].freeze

      DAILY_FIELDS = %w[
        weather_code
        temperature_2m_max
        temperature_2m_min
        precipitation_sum
        precipitation_probability_max
        wind_speed_10m_max
        wind_gusts_10m_max
        wind_direction_10m_dominant
        sunrise
        sunset
      ].freeze

      private

      def fetch(latitude:, longitude:)
        query = URI.encode_www_form(
          latitude: latitude,
          longitude: longitude,
          current: CURRENT_FIELDS.join(","),
          hourly: HOURLY_FIELDS.join(","),
          daily: DAILY_FIELDS.join(","),
          temperature_unit: "celsius",
          wind_speed_unit: "ms",
          precipitation_unit: "mm",
          timezone: "auto",
          forecast_days: 7
        )

        get_json("#{BASE_URL}?#{query}")
      end
    end
  end
end
