class WeatherController < ApplicationController

  def index
    @query = params[:query].to_s.strip
    return if @query.blank?

    @forecast = weather_service.forecast(@query)
  rescue ::Weather::WeatherService::AddressNotFoundError
    @error = "We could not find an address or ZIP/postal code matching #{@query.inspect}. Please try a more specific search."
  rescue ::Weather::WeatherService::AllProvidersFailedError => e
    Rails.logger.warn("[WeatherController] #{e.class}: #{e.message}")
    @error = "Weather data is temporarily unavailable. Please try again later."
  rescue ::AddressResolver::Error => e
    Rails.logger.warn("[WeatherController] #{e.class}: #{e.message}")
    @error = "The address lookup service is temporarily unavailable. Please try again later."
  rescue ArgumentError
    @error = "Please enter a valid address or ZIP/postal code."
  end

  private

  def weather_service
    @weather_service ||= ::Weather::WeatherService.new
  end

end
