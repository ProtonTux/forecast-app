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

  # Address geocoding. Nominatim remains the default; Photon and Open-Meteo
  # Geocoding can be selected per deployment.
  weather.address_resolver = ENV.fetch("ADDRESS_RESOLVER", "nominatim")
  weather.address_cache_ttl = 30.days

  weather.nominatim_url = ENV.fetch("NOMINATIM_URL", "https://nominatim.openstreetmap.org")
  weather.nominatim_user_agent = ENV.fetch("NOMINATIM_USER_AGENT", weather.user_agent)

  weather.photon_url = ENV.fetch("PHOTON_URL", "https://photon.komoot.io")
  weather.photon_user_agent = ENV.fetch("PHOTON_USER_AGENT", weather.user_agent)

  weather.open_meteo_geocoding_url = ENV.fetch(
    "OPEN_METEO_GEOCODING_URL",
    "https://geocoding-api.open-meteo.com"
  )
  weather.open_meteo_geocoding_user_agent = ENV.fetch(
    "OPEN_METEO_GEOCODING_USER_AGENT",
    weather.user_agent
  )
end

Rails.application.config.after_initialize do
  AddressResolution::Factory.validate!(
    AddressResolution::Factory.configured_resolver
  )
end
