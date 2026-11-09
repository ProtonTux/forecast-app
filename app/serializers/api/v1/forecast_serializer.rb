module Api
  module V1
    # Converts the service layer's normalized forecast hash into the stable JSON
    # API contract. Optional sections are always present as arrays or objects.
    class ForecastSerializer
      def initialize(forecast)
        @forecast = forecast
      end

      def as_json
        {
          location: forecast[:location] || {},
          current: forecast[:current],
          hourly: Array(forecast[:hourly]),
          daily: Array(forecast[:daily]),
          sources: Array(forecast[:sources]),
          provider_errors: forecast[:provider_errors] || {},
          generated_at: forecast[:generated_at],
          cache_hit: forecast[:cache_hit]
        }
      end

      private

      attr_reader :forecast
    end
  end
end
