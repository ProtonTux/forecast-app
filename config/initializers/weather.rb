# Configuration for address resolution and weather providers.
#
# Provider responses are normalized to metric units before they are cached:
# temperature in °C, wind speed in m/s, precipitation in mm, pressure in hPa,
# and visibility in km.
Rails.application.config.x.weather.tap do |weather|
  weather.providers = ENV.fetch("WEATHER_PROVIDERS", "noaa,open_meteo")
                           .split(",")
                           .map { |provider| provider.strip.downcase }
                           .reject(&:empty?)

  weather.cache_ttl = 30.minutes
  weather.race_condition_ttl = 10.seconds

  weather.user_agent = ENV.fetch(
    "WEATHER_USER_AGENT",
    "ForecastApp/1.0 (weather forecast application)"
  )

  weather.nominatim_url = ENV.fetch("NOMINATIM_URL", "https://nominatim.openstreetmap.org")
  weather.nominatim_user_agent = ENV.fetch("NOMINATIM_USER_AGENT", weather.user_agent)
  weather.nominatim_cache_ttl = 30.days
end
