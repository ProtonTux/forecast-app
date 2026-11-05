require "time"

module Weather
  # Converts the provider-specific payloads into the application's common
  # weather format. All measurements are metric:
  #
  #   temperature  => °C
  #   wind speed   => m/s
  #   precipitation => mm
  #   pressure     => hPa
  #   visibility   => km
  #
  # Hourly timestamps are normalized to UTC ISO-8601 so that entries from
  # different providers can be combined. Daily entries keep the location's
  # local calendar date.
  class Normalizer
    class Error < StandardError; end

    COMPASS_DIRECTIONS = {
      "N" => 0, "NNE" => 22.5, "NE" => 45, "ENE" => 67.5,
      "E" => 90, "ESE" => 112.5, "SE" => 135, "SSE" => 157.5,
      "S" => 180, "SSW" => 202.5, "SW" => 225, "WSW" => 247.5,
      "W" => 270, "WNW" => 292.5, "NW" => 315, "NNW" => 337.5
    }.freeze

    WEATHER_CODES = {
      0 => "Clear sky",
      1 => "Mainly clear",
      2 => "Partly cloudy",
      3 => "Overcast",
      45 => "Fog",
      48 => "Depositing rime fog",
      51 => "Light drizzle",
      53 => "Moderate drizzle",
      55 => "Dense drizzle",
      56 => "Light freezing drizzle",
      57 => "Dense freezing drizzle",
      61 => "Slight rain",
      63 => "Moderate rain",
      65 => "Heavy rain",
      66 => "Light freezing rain",
      67 => "Heavy freezing rain",
      71 => "Slight snow",
      73 => "Moderate snow",
      75 => "Heavy snow",
      77 => "Snow grains",
      80 => "Slight rain showers",
      81 => "Moderate rain showers",
      82 => "Violent rain showers",
      85 => "Slight snow showers",
      86 => "Heavy snow showers",
      95 => "Thunderstorm",
      96 => "Thunderstorm with slight hail",
      99 => "Thunderstorm with heavy hail"
    }.freeze

    def self.call(provider:, payload:)
      new.call(provider: provider, payload: payload)
    end

    def call(provider:, payload:)
      case provider.to_s
      when "noaa", "nws"
        normalize_noaa(payload)
      when "open_meteo", "open-meteo", "openmeteo"
        normalize_open_meteo(payload)
      else
        raise Error, "Unknown weather provider: #{provider}"
      end
    end
    alias normalize call

    private

    def normalize_noaa(payload)
      payload = stringify_keys(payload)
      points_response = payload["points"].is_a?(Hash) ? payload["points"] : {}
      points = points_response["properties"].is_a?(Hash) ? points_response["properties"] : points_response

      hourly_periods = periods_from(payload["hourly"])
      daily_periods = periods_from(payload["daily"])

      if hourly_periods.empty? && daily_periods.empty?
        direct_periods = periods_from(payload)
        if direct_periods.any?
          if hourly_period?(points["forecastGenerator"], direct_periods)
            hourly_periods = direct_periods
          else
            daily_periods = direct_periods
          end
        end
      end

      hourly = noaa_hourly(hourly_periods)
      daily = noaa_daily(daily_periods)

      {
        source: "noaa",
        location: noaa_location(points_response, points, payload),
        current: hourly.first,
        hourly: hourly,
        daily: daily
      }
    end

    def normalize_open_meteo(payload)
      payload = stringify_keys(payload)
      offset = payload["utc_offset_seconds"].to_i

      {
        source: "open_meteo",
        location: {
          latitude: numeric(payload["latitude"]),
          longitude: numeric(payload["longitude"]),
          timezone: payload["timezone"],
          timezone_abbreviation: payload["timezone_abbreviation"],
          utc_offset_seconds: offset,
          elevation_m: numeric(payload["elevation"])
        }.compact,
        current: open_meteo_current(payload["current"], offset),
        hourly: open_meteo_hourly(payload["hourly"], offset),
        daily: open_meteo_daily(payload["daily"], offset)
      }
    end

    def noaa_hourly(periods)
      periods.filter_map do |period|
        time = utc_time(period["startTime"])
        next if time.nil?

        {
          time: time,
          temperature_c: noaa_temperature(period["temperature"], period["temperatureUnit"]),
          humidity: numeric(period.dig("relativeHumidity", "value")),
          wind_speed_ms: noaa_wind_speed(period["windSpeed"]),
          wind_direction_deg: compass_to_degrees(period["windDirection"]),
          precipitation_probability: numeric(period.dig("probabilityOfPrecipitation", "value")),
          condition: period["shortForecast"],
          icon: period["icon"],
          is_daytime: period["isDaytime"]
        }.compact
      end
    end

    def noaa_daily(periods)
      periods.group_by { |period| local_date(period["startTime"]) }
             .filter_map do |date, day_periods|
        next if date.nil?

        daytime = day_periods.find { |period| period["isDaytime"] } || day_periods.first
        temperatures = day_periods.map do |period|
          noaa_temperature(period["temperature"], period["temperatureUnit"])
        end.compact

        precipitation_probabilities = day_periods.filter_map do |period|
          numeric(period.dig("probabilityOfPrecipitation", "value"))
        end

        wind_speeds = day_periods.filter_map { |period| noaa_wind_speed(period["windSpeed"]) }

        {
          date: date,
          high_c: temperatures.max,
          low_c: temperatures.min,
          precipitation_probability: precipitation_probabilities.max,
          wind_speed_max_ms: wind_speeds.max,
          wind_direction_deg: compass_to_degrees(daytime["windDirection"]),
          condition: daytime["shortForecast"],
          icon: daytime["icon"]
        }.compact
      end
    end

    def open_meteo_current(current, offset)
      return nil unless current.is_a?(Hash) && current.any?

      {
        time: local_iso8601_to_utc(current["time"], offset),
        temperature_c: numeric(current["temperature_2m"]),
        apparent_temperature_c: numeric(current["apparent_temperature"]),
        humidity: numeric(current["relative_humidity_2m"]),
        wind_speed_ms: numeric(current["wind_speed_10m"]),
        wind_direction_deg: numeric(current["wind_direction_10m"]),
        wind_gust_ms: numeric(current["wind_gusts_10m"]),
        precipitation_mm: numeric(current["precipitation"]),
        pressure_hpa: numeric(current["surface_pressure"]),
        visibility_km: meters_to_kilometers(current["visibility"]),
        cloud_cover: numeric(current["cloud_cover"]),
        weather_code: current["weather_code"],
        condition: weather_condition(current["weather_code"]),
        is_daytime: current.key?("is_day") ? current["is_day"].to_i == 1 : nil
      }.compact
    end

    def open_meteo_hourly(hourly, offset)
      return [] unless hourly.is_a?(Hash)

      Array(hourly["time"]).each_index.filter_map do |index|
        time = local_iso8601_to_utc(value_at(hourly, "time", index), offset)
        next if time.nil?

        {
          time: time,
          temperature_c: numeric(value_at(hourly, "temperature_2m", index)),
          apparent_temperature_c: numeric(value_at(hourly, "apparent_temperature", index)),
          humidity: numeric(value_at(hourly, "relative_humidity_2m", index)),
          wind_speed_ms: numeric(value_at(hourly, "wind_speed_10m", index)),
          wind_direction_deg: numeric(value_at(hourly, "wind_direction_10m", index)),
          wind_gust_ms: numeric(value_at(hourly, "wind_gusts_10m", index)),
          precipitation_mm: numeric(value_at(hourly, "precipitation", index)),
          precipitation_probability: numeric(value_at(hourly, "precipitation_probability", index)),
          pressure_hpa: numeric(value_at(hourly, "surface_pressure", index)),
          visibility_km: meters_to_kilometers(value_at(hourly, "visibility", index)),
          cloud_cover: numeric(value_at(hourly, "cloud_cover", index)),
          weather_code: value_at(hourly, "weather_code", index),
          condition: weather_condition(value_at(hourly, "weather_code", index)),
          is_daytime: daytime_value(value_at(hourly, "is_day", index))
        }.compact
      end
    end

    def open_meteo_daily(daily, offset)
      return [] unless daily.is_a?(Hash)

      Array(daily["time"]).each_index.filter_map do |index|
        date = value_at(daily, "time", index)
        next if date.nil?

        {
          date: date,
          high_c: numeric(value_at(daily, "temperature_2m_max", index)),
          low_c: numeric(value_at(daily, "temperature_2m_min", index)),
          precipitation_mm: numeric(value_at(daily, "precipitation_sum", index)),
          precipitation_probability: numeric(value_at(daily, "precipitation_probability_max", index)),
          wind_speed_max_ms: numeric(value_at(daily, "wind_speed_10m_max", index)),
          wind_gust_max_ms: numeric(value_at(daily, "wind_gusts_10m_max", index)),
          wind_direction_deg: numeric(value_at(daily, "wind_direction_10m_dominant", index)),
          sunrise: local_iso8601_to_utc(value_at(daily, "sunrise", index), offset),
          sunset: local_iso8601_to_utc(value_at(daily, "sunset", index), offset),
          weather_code: value_at(daily, "weather_code", index),
          condition: weather_condition(value_at(daily, "weather_code", index))
        }.compact
      end
    end

    def periods_from(response)
      return [] unless response.is_a?(Hash)

      properties = response["properties"]
      periods = properties.is_a?(Hash) ? properties["periods"] : nil
      Array(periods || response["periods"])
    end

    def hourly_period?(generator, periods)
      return true if generator.to_s.downcase.include?("hourly")

      first = periods.first
      start_time = first && first["startTime"]
      end_time = first && first["endTime"]
      return false if start_time.nil? || end_time.nil?

      Time.parse(start_time) && Time.parse(end_time) &&
        (Time.parse(end_time) - Time.parse(start_time)) <= 3.hours
    rescue ArgumentError
      false
    end

    def noaa_location(points_response, points, payload)
      coordinates = points_response.dig("geometry", "coordinates") ||
                    payload.dig("geometry", "coordinates")
      coordinates = nil unless coordinates.is_a?(Array)
      relative_location = points.dig("relativeLocation", "properties") || {}

      {
        latitude: coordinates && numeric(coordinates[1]),
        longitude: coordinates && numeric(coordinates[0]),
        timezone: points["timeZone"] || points["timezone"],
        city: relative_location["city"],
        region: relative_location["state"]
      }.compact
    end

    def noaa_temperature(value, unit)
      return nil if value.nil?

      temperature = Float(value)
      if unit.to_s.upcase.start_with?("F")
        ((temperature - 32) * 5.0 / 9.0).round(2)
      else
        temperature.round(2)
      end
    rescue ArgumentError, TypeError
      nil
    end

    def noaa_wind_speed(value)
      return nil if value.nil?

      speeds = value.to_s.scan(/\d+(?:\.\d+)?/).map(&:to_f)
      return nil if speeds.empty?

      speed = speeds.sum / speeds.length
      multiplier = wind_speed_multiplier(value)

      (speed * multiplier).round(2)
    end

    def wind_speed_multiplier(value)
      if value.to_s.match?(/km\/h/i)
        1.0 / 3.6
      elsif value.to_s.match?(/mph|mi\/h/i)
        0.44704
      else
        1.0
      end
    end

    def compass_to_degrees(value)
      return nil if value.nil?
      return value.to_f.round(2) if value.to_s.match?(/\A-?\d+(?:\.\d+)?\z/)

      COMPASS_DIRECTIONS[value.to_s.upcase]
    end

    def numeric(value)
      return nil if value.nil? || value == ""

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def meters_to_kilometers(value)
      meters = numeric(value)
      meters && (meters / 1000.0).round(3)
    end

    def weather_condition(code)
      return nil if code.nil?

      WEATHER_CODES.fetch(code.to_i, "Unknown")
    end

    def daytime_value(value)
      return nil if value.nil?

      value.to_i == 1
    end

    def value_at(hash, key, index)
      values = hash[key]
      return nil unless values.is_a?(Array)

      values[index]
    end

    def local_date(value)
      return nil if value.nil?

      value.to_s[0, 10]
    end

    def utc_time(value)
      return nil if value.nil?

      Time.parse(value.to_s).utc.iso8601
    rescue ArgumentError
      value.to_s
    end

    def local_iso8601_to_utc(value, offset)
      return nil if value.nil?

      string = value.to_s
      if string.match?(/(?:Z|[+-]\d{2}:?\d{2})\z/)
        Time.parse(string).utc.iso8601
      else
        Time.parse("#{string}#{utc_offset_string(offset)}").utc.iso8601
      end
    rescue ArgumentError
      string
    end

    def utc_offset_string(offset)
      sign = offset.negative? ? "-" : "+"
      absolute = offset.abs
      format("%s%02d:%02d", sign, absolute / 3600, (absolute % 3600) / 60)
    end

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), result|
          result[key.to_s] = stringify_keys(child)
        end
      when Array
        value.map { |child| stringify_keys(child) }
      else
        value
      end
    end
  end
end
