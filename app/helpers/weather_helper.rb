module WeatherHelper
  SOURCE_NAMES = {
    "noaa" => "NOAA",
    "open_meteo" => "Open-Meteo"
  }.freeze

  def weather_location_name(location)
    parts = [
      location[:city],
      location[:region],
      location[:postal_code],
      location[:country]
    ].compact_blank

    parts.presence&.join(", ") || "Selected location"
  end

  def weather_coordinates(location)
    latitude = location[:latitude]
    longitude = location[:longitude]

    return "—" if latitude.nil? || longitude.nil?

    format("%.4f, %.4f", latitude, longitude)
  end

  def weather_source_name(source)
    SOURCE_NAMES.fetch(source.to_s, source.to_s.humanize)
  end

  def weather_measurement(value, unit, precision: 1)
    return "—" unless value.is_a?(Numeric)

    "#{number_with_precision(value, precision: precision)} #{unit}"
  end

  def weather_percentage(value)
    weather_measurement(value, "%", precision: 0)
  end

  def weather_wind(speed, direction)
    parts = []
    parts << weather_measurement(speed, "m/s") if speed.present?
    parts << "#{number_with_precision(direction, precision: 0)}°" if direction.present?

    parts.presence&.join(" ") || "—"
  end

  def weather_time(value, time_zone = nil)
    return "—" if value.blank?

    time = Time.zone.parse(value.to_s)
    return value.to_s if time.nil?

    zone = ActiveSupport::TimeZone[time_zone] if time_zone.present?
    time = time.in_time_zone(zone) if zone

    time.strftime("%a, %b %-d %Y, %-H:%M %Z")
  rescue ArgumentError, TypeError
    value.to_s
  end

  def weather_date(value)
    return "—" if value.blank?

    Date.parse(value.to_s).strftime("%a, %b %-d")
  rescue ArgumentError, TypeError
    value.to_s
  end
end
