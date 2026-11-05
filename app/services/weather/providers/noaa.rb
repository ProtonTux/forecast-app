module Weather
  module Providers
    # Adapter for the National Weather Service (NOAA) API.
    #
    # NOAA returns US customary units, so the Normalizer converts the values
    # to metric before they leave this provider.
    class Noaa < Base
      BASE_URL = "https://api.weather.gov"

      private

      def fetch(latitude:, longitude:)
        points = get_json("#{BASE_URL}/points/#{coordinate(latitude)},#{coordinate(longitude)}")
        properties = points["properties"]

        unless properties.is_a?(Hash)
          raise Error, "NOAA points response did not include a properties object"
        end

        hourly_url = properties["forecastHourly"]
        daily_url = properties["forecast"]

        if hourly_url.blank? && daily_url.blank?
          raise Error, "NOAA points response did not include a forecast URL"
        end

        {
          "points" => points,
          "hourly" => hourly_url.present? ? get_json(hourly_url) : nil,
          "daily" => daily_url.present? ? get_json(daily_url) : nil
        }
      end

      def coordinate(value)
        format("%.4f", Float(value))
      rescue ArgumentError, TypeError
        raise Error, "Invalid coordinate: #{value.inspect}"
      end
    end
  end
end
