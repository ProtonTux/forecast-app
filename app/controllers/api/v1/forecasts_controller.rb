module Api
  module V1
    # Serves the combined forecast as JSON.
    #
    #   GET /api/v1/forecasts?query=1801+West+International+Speedway+Blvd...
    class ForecastsController < BaseController
      def index
        @query = params[:query].to_s.strip
        raise ArgumentError, "query is required" if @query.blank?

        forecast = weather_service.forecast(@query)
        render json: { data: Api::V1::ForecastSerializer.new(forecast).as_json }
      end

      private

      def weather_service
        @weather_service ||= Weather::WeatherService.new
      end
    end
  end
end
