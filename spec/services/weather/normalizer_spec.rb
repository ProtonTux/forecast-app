require "rails_helper"

RSpec.describe Weather::Normalizer do
  subject(:normalizer) { described_class.new }

  describe "#call" do
    context "with an Open-Meteo payload" do
      let(:payload) do
        {
          "latitude" => 1,
          "longitude" => 2,
          "utc_offset_seconds" => -18_000,
          "timezone" => "America/New_York",
          "timezone_abbreviation" => "GMT-5",
          "elevation" => 20,
          "current" => {
            "time" => "2026-11-03T21:30",
            "temperature_2m" => 14.7,
            "relative_humidity_2m" => 82,
            "apparent_temperature" => 14.7,
            "precipitation" => 0,
            "weather_code" => 0,
            "surface_pressure" => 1021,
            "wind_speed_10m" => 0.92,
            "wind_direction_10m" => 332,
            "wind_gusts_10m" => 2.8,
            "visibility" => 17_700,
            "is_day" => 0
          },
          "hourly" => {
            "time" => [ "2026-11-03T21:00", "2026-11-03T22:00" ],
            "temperature_2m" => [ 15, 14 ],
            "relative_humidity_2m" => [ 80, 82 ],
            "apparent_temperature" => [ 15, 14 ],
            "precipitation" => [ 0, 0.4 ],
            "precipitation_probability" => [ 5, 20 ],
            "weather_code" => [ 0, 61 ],
            "surface_pressure" => [ 1020, 1019 ],
            "wind_speed_10m" => [ 1.5, 2.0 ],
            "wind_direction_10m" => [ 330, 340 ],
            "wind_gusts_10m" => [ 3.0, 4.0 ],
            "visibility" => [ 20_000, 15_000 ],
            "is_day" => [ 0, 0 ]
          },
          "daily" => {
            "time" => [ "2026-11-03" ],
            "temperature_2m_max" => [ 18 ],
            "temperature_2m_min" => [ 8 ],
            "precipitation_sum" => [ 1.2 ],
            "precipitation_probability_max" => [ 20 ],
            "wind_speed_10m_max" => [ 4.5 ],
            "wind_gusts_10m_max" => [ 8.0 ],
            "wind_direction_10m_dominant" => [ 315 ],
            "sunrise" => [ "2026-11-03T06:30" ],
            "sunset" => [ "2026-11-03T17:00" ],
            "weather_code" => [ 1 ]
          }
        }
      end

      it "converts values to metric units and timestamps to UTC" do
        result = normalizer.call(provider: :open_meteo, payload: payload)

        expect(result[:source]).to eq("open_meteo")
        expect(result[:location]).to include(
          latitude: 1.0,
          longitude: 2.0,
          timezone: "America/New_York",
          timezone_abbreviation: "GMT-5",
          utc_offset_seconds: -18_000,
          elevation_m: 20.0
        )

        expect(result[:current]).to include(
          time: "2026-11-04T02:30:00Z",
          temperature_c: 14.7,
          humidity: 82.0,
          visibility_km: 17.7,
          weather_code: 0,
          condition: "Clear sky",
          is_daytime: false
        )

        expect(result[:hourly].map { |entry| entry[:time] }).to eq(
          [ "2026-11-04T02:00:00Z", "2026-11-04T03:00:00Z" ]
        )
        expect(result[:hourly].last).to include(
          temperature_c: 14.0,
          precipitation_mm: 0.4,
          precipitation_probability: 20.0,
          visibility_km: 15.0,
          condition: "Slight rain"
        )

        expect(result[:daily].first).to include(
          date: "2026-11-03",
          high_c: 18.0,
          low_c: 8.0,
          precipitation_mm: 1.2,
          precipitation_probability: 20.0,
          wind_speed_max_ms: 4.5,
          sunrise: "2026-11-03T11:30:00Z",
          sunset: "2026-11-03T22:00:00Z",
          condition: "Mainly clear"
        )
      end

      it "accepts provider aliases" do
        expect(normalizer.call(provider: "open-meteo", payload: payload)[:source]).to eq("open_meteo")
        expect(normalizer.call(provider: "openmeteo", payload: payload)[:source]).to eq("open_meteo")
      end

      it "handles empty current, hourly, and daily sections" do
        result = normalizer.call(provider: :open_meteo, payload: { "utc_offset_seconds" => 0 })

        expect(result[:current]).to be_nil
        expect(result[:hourly]).to eq([])
        expect(result[:daily]).to eq([])
      end
    end

    context "with a NOAA payload" do
      let(:payload) do
        {
          "points" => {
            "geometry" => { "coordinates" => [ -81.0700, 29.1858 ] },
            "properties" => {
              "timeZone" => "America/New_York",
              "relativeLocation" => {
                "properties" => { "city" => "Daytona Beach", "state" => "FL" }
              }
            }
          },
          "hourly" => {
            "properties" => {
              "periods" => [
                {
                  "startTime" => "2026-11-03T20:00:00-05:00",
                  "temperature" => 59,
                  "temperatureUnit" => "F",
                  "relativeHumidity" => { "value" => 93 },
                  "windSpeed" => "3 mph",
                  "windDirection" => "S",
                  "probabilityOfPrecipitation" => { "value" => 2 },
                  "shortForecast" => "Clear",
                  "icon" => "https://api.weather.gov/icons/land/night/clear",
                  "isDaytime" => false
                },
                {
                  "startTime" => "2026-11-03T21:00:00-05:00",
                  "temperature" => 57,
                  "temperatureUnit" => "F",
                  "windSpeed" => "0 to 5 mph",
                  "windDirection" => "SSW",
                  "shortForecast" => "Mostly Clear",
                  "isDaytime" => false
                }
              ]
            }
          },
          "daily" => {
            "properties" => {
              "periods" => [
                {
                  "startTime" => "2026-11-03T19:00:00-05:00",
                  "temperature" => 53,
                  "temperatureUnit" => "F",
                  "isDaytime" => false,
                  "windSpeed" => "5 mph",
                  "windDirection" => "S",
                  "probabilityOfPrecipitation" => { "value" => 2 },
                  "shortForecast" => "Mostly Clear"
                },
                {
                  "startTime" => "2026-11-04T06:00:00-05:00",
                  "temperature" => 76,
                  "temperatureUnit" => "F",
                  "isDaytime" => true,
                  "windSpeed" => "2 to 9 mph",
                  "windDirection" => "S",
                  "probabilityOfPrecipitation" => { "value" => 5 },
                  "shortForecast" => "Mostly Sunny"
                }
              ]
            }
          }
        }
      end

      it "converts US customary units and compiles daily summaries" do
        result = normalizer.call(provider: :noaa, payload: payload)

        expect(result[:source]).to eq("noaa")
        expect(result[:location]).to include(
          latitude: 29.1858,
          longitude: -81.0700,
          timezone: "America/New_York",
          city: "Daytona Beach",
          region: "FL"
        )

        expect(result[:current]).to include(
          time: "2026-11-04T01:00:00Z",
          temperature_c: 15.0,
          humidity: 93.0,
          wind_speed_ms: 1.34,
          wind_direction_deg: 180.0,
          precipitation_probability: 2.0,
          condition: "Clear",
          is_daytime: false
        )

        expect(result[:daily].map { |entry| entry[:date] }).to eq(%w[2026-11-03 2026-11-04])

        daily = result[:daily].last
        expect(daily).to include(
          high_c: 24.44,
          low_c: 24.44,
          precipitation_probability: 5.0,
          wind_speed_max_ms: 2.46,
          wind_direction_deg: 180.0,
          condition: "Mostly Sunny"
        )
      end

      it "accepts the NWS provider alias" do
        expect(normalizer.call(provider: "nws", payload: payload)[:source]).to eq("noaa")
      end

      it "detects hourly periods from a direct period list" do
        result = normalizer.call(
          provider: :noaa,
          payload: {
            "forecastGenerator" => "HourlyForecastGenerator",
            "periods" => [
              {
                "startTime" => "2026-11-03T12:00:00Z",
                "endTime" => "2026-11-03T13:00:00Z",
                "temperature" => 20,
                "temperatureUnit" => "C",
                "windSpeed" => "2 m/s"
              }
            ]
          }
        )

        expect(result[:hourly].length).to eq(1)
        expect(result[:hourly].first[:temperature_c]).to eq(20.0)
        expect(result[:daily]).to eq([])
      end
    end

    it "raises for an unknown provider" do
      expect { normalizer.call(provider: :unknown, payload: {}) }
        .to raise_error(Weather::Normalizer::Error, /Unknown weather provider/)
    end
  end

  describe ".call" do
    it "delegates to an instance" do
      expect(described_class.call(provider: :open_meteo, payload: {})[:source]).to eq("open_meteo")
    end
  end

  describe "edge cases" do
    it "treats direct periods as daily when their length cannot be parsed" do
      result = normalizer.call(
        provider: :noaa,
        payload: {
          "periods" => [ {
            "startTime" => "not a time",
            "endTime" => "also not a time",
            "temperature" => 20,
            "temperatureUnit" => "C"
          } ]
        }
      )

      expect(result[:hourly]).to eq([])
      expect(result[:daily].length).to eq(1)
    end

    it "ignores invalid NOAA temperatures and converts km/h wind speeds" do
      result = normalizer.call(
        provider: :noaa,
        payload: {
          "hourly" => {
            "periods" => [ {
              "startTime" => "not a time",
              "temperature" => "warm",
              "temperatureUnit" => "C",
              "windSpeed" => "10 km/h"
            } ]
          }
        }
      )

      expect(result[:hourly].first[:time]).to eq("not a time")
      expect(result[:hourly].first[:temperature_c]).to be_nil
      expect(result[:hourly].first[:wind_speed_ms]).to eq(2.78)
    end

    it "handles invalid numbers, explicit offsets, and invalid local timestamps" do
      result = normalizer.call(
        provider: :open_meteo,
        payload: {
          "utc_offset_seconds" => 0,
          "current" => {
            "time" => "2026-11-03T12:00:00Z",
            "temperature_2m" => "hot"
          },
          "hourly" => {
            "time" => [ "25:99" ]
          }
        }
      )

      expect(result[:current]).to include(time: "2026-11-03T12:00:00Z")
      expect(result[:current][:temperature_c]).to be_nil
      expect(result[:hourly].first[:time]).to eq("25:99")
    end
  end
end
