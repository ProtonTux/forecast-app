require "rails_helper"

RSpec.describe Weather::Providers::OpenMeteo do
  subject(:provider) { described_class.new }

  let(:latitude) { 52.52 }
  let(:longitude) { 13.405 }
  let(:base_url) { "https://api.open-meteo.com/v1/forecast" }
  let(:request_url) { %r{\Ahttps://api\.open-meteo\.com/v1/forecast\?} }

  let(:payload) do
    {
      "latitude" => latitude,
      "longitude" => longitude,
      "utc_offset_seconds" => 3600,
      "timezone" => "Europe/Berlin",
      "timezone_abbreviation" => "GMT+1",
      "elevation" => 34,
      "current" => {
        "time" => "2026-11-03T13:30",
        "temperature_2m" => 11.2,
        "relative_humidity_2m" => 70,
        "apparent_temperature" => 9.8,
        "precipitation" => 0.2,
        "weather_code" => 3,
        "cloud_cover" => 85,
        "surface_pressure" => 1008,
        "wind_speed_10m" => 4.2,
        "wind_direction_10m" => 250,
        "wind_gusts_10m" => 7.8,
        "visibility" => 12_400,
        "is_day" => 1
      },
      "hourly" => {
        "time" => [ "2026-11-03T13:00" ],
        "temperature_2m" => [ 11.0 ],
        "relative_humidity_2m" => [ 71 ],
        "apparent_temperature" => [ 9.5 ],
        "precipitation" => [ 0.1 ],
        "precipitation_probability" => [ 30 ],
        "weather_code" => [ 61 ],
        "cloud_cover" => [ 90 ],
        "surface_pressure" => [ 1007 ],
        "wind_speed_10m" => [ 4.0 ],
        "wind_direction_10m" => [ 250 ],
        "wind_gusts_10m" => [ 8.0 ],
        "visibility" => [ 10_000 ],
        "is_day" => [ 1 ]
      },
      "daily" => {
        "time" => [ "2026-11-03" ],
        "weather_code" => [ 61 ],
        "temperature_2m_max" => [ 13.0 ],
        "temperature_2m_min" => [ 6.0 ],
        "precipitation_sum" => [ 2.4 ],
        "precipitation_probability_max" => [ 65 ],
        "wind_speed_10m_max" => [ 6.5 ],
        "wind_gusts_10m_max" => [ 10.0 ],
        "wind_direction_10m_dominant" => [ 245 ],
        "sunrise" => [ "2026-11-03T07:05" ],
        "sunset" => [ "2026-11-03T16:30" ]
      }
    }
  end

  describe "#forecast" do
    it "requests metric units and normalizes the response" do
      stub_request(:get, request_url)
        .with(query: hash_including(
          "latitude" => latitude.to_s,
          "longitude" => longitude.to_s,
          "temperature_unit" => "celsius",
          "wind_speed_unit" => "ms",
          "precipitation_unit" => "mm",
          "timezone" => "auto",
          "forecast_days" => "7"
        ))
        .to_return(status: 200, body: payload.to_json)

      result = provider.forecast(latitude: latitude, longitude: longitude)

      expect(
        a_request(:get, request_url).with(query: hash_including(
          "current" => Weather::Providers::OpenMeteo::CURRENT_FIELDS.join(","),
          "hourly" => Weather::Providers::OpenMeteo::HOURLY_FIELDS.join(","),
          "daily" => Weather::Providers::OpenMeteo::DAILY_FIELDS.join(",")
        ))
      ).to have_been_made.once

      expect(result[:source]).to eq("open_meteo")
      expect(result[:location]).to include(
        latitude: latitude,
        longitude: longitude,
        timezone: "Europe/Berlin",
        elevation_m: 34.0
      )
      expect(result[:current]).to include(
        time: "2026-11-03T12:30:00Z",
        temperature_c: 11.2,
        humidity: 70.0,
        wind_speed_ms: 4.2,
        visibility_km: 12.4,
        condition: "Overcast",
        is_daytime: true
      )
      expect(result[:hourly].first).to include(
        time: "2026-11-03T12:00:00Z",
        precipitation_probability: 30.0,
        condition: "Slight rain"
      )
      expect(result[:daily].first).to include(
        date: "2026-11-03",
        high_c: 13.0,
        low_c: 6.0,
        precipitation_mm: 2.4,
        sunrise: "2026-11-03T06:05:00Z",
        sunset: "2026-11-03T15:30:00Z"
      )
    end

    it "sends a descriptive User-Agent" do
      stub_request(:get, request_url).to_return(status: 200, body: payload.to_json)

      provider.forecast(latitude: latitude, longitude: longitude)

      expect(
        a_request(:get, request_url).with do |request|
          request.headers["User-Agent"].to_s.include?("ForecastApp")
        end
      ).to have_been_made
    end
  end

  describe "HTTP errors" do
    it "raises a provider error for a non-success response" do
      stub_request(:get, request_url).to_return(status: 500, body: "Internal Server Error")

      expect { provider.forecast(latitude: latitude, longitude: longitude) }
        .to raise_error(Weather::Providers::Error, /open_meteo request failed with 500/)
    end

    it "raises a provider error for invalid JSON" do
      stub_request(:get, request_url).to_return(status: 200, body: "not json")

      expect { provider.forecast(latitude: latitude, longitude: longitude) }
        .to raise_error(Weather::Providers::Error, /open_meteo returned invalid JSON/)
    end

    it "raises a provider error when the network request fails" do
      stub_request(:get, request_url).to_raise(SocketError.new("getaddrinfo failed"))

      expect { provider.forecast(latitude: latitude, longitude: longitude) }
        .to raise_error(Weather::Providers::Error, /open_meteo request failed/)
    end
  end
end
