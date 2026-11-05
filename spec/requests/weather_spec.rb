require "rails_helper"

RSpec.describe "Weather interface", type: :request do
  let(:service) { instance_double(Weather::WeatherService) }
  let(:query) do
    "1801 West International Speedway Blvd, Daytona Beach, Florida, United States 32114"
  end

  let(:forecast) do
    {
      location: {
        city: "Daytona Beach",
        region: "Florida",
        postal_code: "32114",
        country: "US",
        timezone: "America/New_York",
        latitude: 29.1858,
        longitude: -81.0700
      },
      current: {
        time: "2026-11-04T12:00:00Z",
        condition: "Sunny",
        temperature_c: 25.0,
        apparent_temperature_c: 26.0,
        humidity: 60.0,
        wind_speed_ms: 3.5,
        wind_direction_deg: 90.0,
        wind_gust_ms: 5.0,
        precipitation_mm: 0.0,
        pressure_hpa: 1015.0,
        visibility_km: 16.0,
        cloud_cover: 10.0
      },
      hourly: [
        {
          time: "2026-11-04T13:00:00Z",
          condition: "Sunny",
          temperature_c: 26.0,
          precipitation_mm: 0.0,
          precipitation_probability: 5.0,
          wind_speed_ms: 4.0,
          wind_direction_deg: 100.0,
          humidity: 58.0
        }
      ],
      daily: [
        {
          date: "2026-11-04",
          condition: "Mostly sunny",
          high_c: 28.0,
          low_c: 19.0,
          precipitation_mm: 0.0,
          precipitation_probability: 10.0,
          wind_speed_max_ms: 6.0
        }
      ],
      sources: [ "noaa", "custom_provider" ],
      provider_errors: { "open_meteo" => "Timeout" },
      generated_at: "2026-11-04T12:00:00Z",
      cache_hit: true
    }
  end

  before do
    allow(Weather::WeatherService).to receive(:new).and_return(service)
  end

  it "shows the search form" do
    get "/weather"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Address or ZIP/postal code")
    expect(response.body).to include("Get forecast")
  end

  it "shows a forecast for a resolved address or ZIP/postal code" do
    allow(service).to receive(:forecast).with(query).and_return(forecast)

    get "/weather", params: { query: query, commit: "Get forecast" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Daytona Beach, Florida, 32114, US")
    expect(response.body).to include("29.1858, -81.0700")
    expect(response.body).to include("Current temperature")
    expect(response.body).to include("Current conditions")
    expect(response.body).to include("25.0 °C")
    expect(response.body).to include("Hourly forecast")
    expect(response.body).to include("Daily forecast")
    expect(response.body).to include("NOAA")
    expect(response.body).to include("Custom provider")
    expect(response.body).to include("Partial data")
    expect(response.body).to include("Open-Meteo: Timeout")
    expect(response.body).to include("Cached")
  end

  it "marks a newly fetched forecast" do
    allow(service).to receive(:forecast).with(query).and_return(forecast.merge(cache_hit: false))

    get "/weather", params: { query: query }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("New request")
    expect(response.body).not_to include(">Cached<")
  end

  it "shows the page with missing forecast sections" do
    allow(service).to receive(:forecast).and_return(
      location: {},
      current: nil,
      hourly: [],
      daily: [],
      sources: [],
      provider_errors: nil,
      generated_at: nil
    )

    get "/weather", params: { query: query }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Selected location")
    expect(response.body).to include("Time zone: Unknown")
    expect(response.body).to include("Sources: Unknown")
    expect(response.body).to include("No hourly forecast data is available.")
    expect(response.body).to include("No daily forecast data is available.")
  end

  it "explains when the address cannot be resolved" do
    allow(service).to receive(:forecast)
      .and_raise(Weather::WeatherService::AddressNotFoundError)

    get "/weather", params: { query: "nowhere" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("could not find an address")
  end

  it "explains when every weather provider fails" do
    allow(service).to receive(:forecast)
      .and_raise(Weather::WeatherService::AllProvidersFailedError, "all providers down")

    get "/weather", params: { query: query }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Weather data is temporarily unavailable")
  end

  it "explains when the address lookup service fails" do
    allow(service).to receive(:forecast).and_raise(AddressResolver::Error, "lookup down")

    get "/weather", params: { query: query }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("address lookup service is temporarily unavailable")
  end

  it "explains when the query is invalid" do
    allow(service).to receive(:forecast).and_raise(ArgumentError, "invalid coordinates")

    get "/weather", params: { query: query }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Please enter a valid address")
  end

  it "does not mask unexpected failures" do
    allow(service).to receive(:forecast).and_raise(StandardError, "unexpected failure")

    expect do
      get "/weather", params: { query: query }
    end.to raise_error(StandardError, "unexpected failure")
  end
end
