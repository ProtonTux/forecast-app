module Api
  module V1
    # Base controller for the public JSON API. It intentionally inherits from
    # ActionController::API so API clients are not subject to the HTML browser
    # gating used by ApplicationController.
    class BaseController < ActionController::API
      # Declare StandardError first so the more specific handlers below take
      # priority. Rails searches rescue handlers in reverse declaration order.
      rescue_from StandardError, with: :render_unexpected_error
      rescue_from ArgumentError, with: :render_invalid_query
      rescue_from AddressResolver::Error, with: :render_address_lookup_error
      rescue_from Weather::WeatherService::AddressNotFoundError, with: :render_address_not_found
      rescue_from Weather::WeatherService::AllProvidersFailedError, with: :render_weather_unavailable

      private

      def render_invalid_query(_error)
        render_error(
          422,
          "invalid_query",
          "Please enter a valid address or ZIP/postal code."
        )
      end

      def render_address_not_found(_error)
        render_error(
          404,
          "address_not_found",
          "We could not find an address or ZIP/postal code matching #{@query.inspect}. " \
          "Please try a more specific search."
        )
      end

      def render_address_lookup_error(error)
        log_error(error)
        render_error(
          503,
          "address_lookup_unavailable",
          "The address lookup service is temporarily unavailable. Please try again later."
        )
      end

      def render_weather_unavailable(error)
        log_error(error)
        render_error(
          503,
          "weather_unavailable",
          "Weather data is temporarily unavailable. Please try again later."
        )
      end

      def render_unexpected_error(error)
        log_error(error)
        render_error(
          500,
          "internal_error",
          "Something went wrong while preparing the forecast. Please try again."
        )
      end

      def render_error(status, code, message)
        render json: { error: { code: code, message: message } }, status: status
      end

      def log_error(error)
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

        Rails.logger.warn("[Api::V1::BaseController] #{error.class}: #{error.message}")
      end
    end
  end
end
