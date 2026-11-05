require "rails_helper"

RSpec.describe Weather::Providers::Noaa do
  subject(:provider) { described_class.new }

  let(:latitude) { 29.1858 }
  let(:longitude) { -81.0700 }
  let(:points_url) { "https://api.weather.gov/points/29.1858,-81.0700" }
  let(:hourly_url) { "https://api.weather.gov/gridpoints/LWX/96,70/forecast/hourly" }
  let(:daily_url) { "https://api.weather.gov/gridpoints/LWX/96,70/forecast" }

  let(:points_response) do
    {
      "geometry" => { "coordinates" => [ longitude, latitude ] },
      "properties" => {
        "forecastHourly" => hourly_url,
        "forecast" => daily_url,
        "timeZone" => "America/New_York",
        "relativeLocation" => {
          "properties" => { "city" => "Daytona Beach", "state" => "FL" }
        }
      }
    }
  end

  let(:hourly_response) do
    {
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
            "isDaytime" => false
          }
        ]
      }
    }
  end

  let(:daily_response) do
    {
      "properties" => {
        "periods" => [
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
  end

  def stub_full_forecast
    stub_request(:get, points_url).to_return(status: 200, body: points_response.to_json)
    stub_request(:get, hourly_url).to_return(status: 200, body: hourly_response.to_json)
    stub_request(:get, daily_url).to_return(status: 200, body: daily_response.to_json)
  end

  describe "#forecast" do
    it "fetches the points, hourly, and daily endpoints and normalizes the result" do
      stub_full_forecast

      result = provider.forecast(latitude: latitude, longitude: longitude)

      expect(a_request(:get, points_url)).to have_been_made.once
      expect(a_request(:get, hourly_url)).to have_been_made.once
      expect(a_request(:get, daily_url)).to have_been_made.once

      expect(result[:source]).to eq("noaa")
      expect(result[:location]).to include(
        latitude: latitude,
        longitude: longitude,
        timezone: "America/New_York",
        city: "Daytona Beach",
        region: "FL"
      )
      expect(result[:current]).to include(
        temperature_c: 15.0,
        wind_speed_ms: 1.34,
        condition: "Clear"
      )
      expect(result[:daily].first).to include(
        date: "2026-11-04",
        high_c: 24.44,
        condition: "Mostly Sunny"
      )
    end

    it "sends a descriptive User-Agent and accepts geo JSON" do
      stub_full_forecast

      provider.forecast(latitude: latitude, longitude: longitude)

      expect(
        a_request(:get, points_url).with do |request|
          request.headers["User-Agent"].to_s.include?("ForecastApp") &&
            request.headers["Accept"].to_s.include?("application/geo+json")
        end
      ).to have_been_made
    end

    it "uses a custom user agent when provided" do
      provider = described_class.new(user_agent: "ForecastApp/1.0 (spec)")
      stub_full_forecast

      provider.forecast(latitude: latitude, longitude: longitude)

      expect(
        a_request(:get, points_url).with do |request|
          request.headers["User-Agent"] == "ForecastApp/1.0 (spec)"
        end
      ).to have_been_made
    end

    it "formats coordinates to four decimal places" do
      stub_full_forecast

      provider.forecast(latitude: 29.18578, longitude: -81.07002)

      expect(a_request(:get, "https://api.weather.gov/points/29.1858,-81.0700")).to have_been_made
    end

    it "skips the daily endpoint when NOAA does not provide one" do
      points_response["properties"].delete("forecast")
      stub_request(:get, points_url).to_return(status: 200, body: points_response.to_json)
      stub_request(:get, hourly_url).to_return(status: 200, body: hourly_response.to_json)

      result = provider.forecast(latitude: latitude, longitude: longitude)

      expect(a_request(:get, daily_url)).not_to have_been_made
      expect(result[:daily]).to eq([])
    end

    it "raises when the points response has no properties" do
      stub_request(:get, points_url).to_return(status: 200, body: { "geometry" => {} }.to_json)

      expect { provider.forecast(latitude: latitude, longitude: longitude) }
        .to raise_error(Weather::Providers::Error, /did not include a properties object/)
    end

    it "raises when the points response has no forecast URLs" do
      points_response["properties"].delete("forecastHourly")
      points_response["properties"].delete("forecast")
      stub_request(:get, points_url).to_return(status: 200, body: points_response.to_json)

      expect { provider.forecast(latitude: latitude, longitude: longitude) }
        .to raise_error(Weather::Providers::Error, /did not include a forecast URL/)
    end
  end

  describe "HTTP errors" do
    it "raises a provider error for a non-success response" do
      stub_request(:get, points_url)
        .to_return(status: 503, body: "Service Unavailable", headers: { "Content-Type" => "text/plain" })

      expect { provider.forecast(latitude: latitude, longitude: longitude) }
        .to raise_error(Weather::Providers::Error, /noaa request failed with 503/)
    end

    it "raises a provider error for invalid JSON" do
      stub_request(:get, points_url).to_return(status: 200, body: "{not-json")

      expect { provider.forecast(latitude: latitude, longitude: longitude) }
        .to raise_error(Weather::Providers::Error, /noaa returned invalid JSON/)
    end

    it "raises a provider error for an invalid coordinate" do
      expect { provider.forecast(latitude: "north", longitude: longitude) }
        .to raise_error(Weather::Providers::Error, /Invalid coordinate/)
    end
  end
end
