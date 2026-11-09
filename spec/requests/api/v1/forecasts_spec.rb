require "rails_helper"

RSpec.describe "API v1 forecasts", type: :request do
  let(:service) { instance_double(Weather::WeatherService) }
  let(:query) do
    "1801 West International Speedway Blvd, Daytona Beach, Florida, United States 32114"
  end
  let(:endpoint) { "/api/v1/forecasts" }

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
        humidity: 60.0
      },
      hourly: [
        {
          time: "2026-11-04T13:00:00Z",
          condition: "Sunny",
          temperature_c: 26.0
        }
      ],
      daily: [
        {
          date: "2026-11-04",
          condition: "Mostly sunny",
          high_c: 28.0,
          low_c: 19.0
        }
      ],
      sources: [ "noaa", "open_meteo" ],
      provider_errors: { "open_meteo" => "Timeout" },
      generated_at: "2026-11-04T12:00:00Z",
      cache_hit: true
    }
  end

  before do
    allow(Weather::WeatherService).to receive(:new).and_return(service)
  end

  def json_body
    JSON.parse(response.body)
  end

  it "returns a forecast for a resolved address" do
    allow(service).to receive(:forecast).with(query).and_return(forecast)

    get endpoint, params: { query: query }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(json_body.dig("data", "location")).to include(
      "city" => "Daytona Beach",
      "postal_code" => "32114",
      "country" => "US"
    )
    expect(json_body.dig("data", "current")).to include(
      "temperature_c" => 25.0,
      "condition" => "Sunny"
    )
    expect(json_body.dig("data", "hourly").length).to eq(1)
    expect(json_body.dig("data", "daily").first).to include("high_c" => 28.0)
    expect(json_body.dig("data", "sources")).to eq([ "noaa", "open_meteo" ])
    expect(json_body.dig("data", "provider_errors")).to eq("open_meteo" => "Timeout")
    expect(json_body.dig("data", "generated_at")).to eq("2026-11-04T12:00:00Z")
    expect(json_body.dig("data", "cache_hit")).to be(true)
  end

  it "normalizes missing optional sections" do
    allow(service).to receive(:forecast).with(query).and_return(
      location: nil,
      current: nil,
      hourly: nil,
      daily: nil,
      sources: nil,
      provider_errors: nil,
      generated_at: nil,
      cache_hit: false
    )

    get endpoint, params: { query: query }

    expect(response).to have_http_status(:ok)
    expect(json_body["data"]).to include(
      "location" => {},
      "current" => nil,
      "hourly" => [],
      "daily" => [],
      "sources" => [],
      "provider_errors" => {},
      "generated_at" => nil,
      "cache_hit" => false
    )
  end

  it "strips surrounding whitespace from the query" do
    allow(service).to receive(:forecast).with(query).and_return(forecast)

    get endpoint, params: { query: "  #{query}  " }

    expect(response).to have_http_status(:ok)
    expect(service).to have_received(:forecast).with(query)
  end

  it "rejects a missing query" do
    get endpoint

    expect(response).to have_http_status(422)
    expect(json_body.dig("error", "code")).to eq("invalid_query")
    expect(json_body.dig("error", "message")).to include("valid address")
  end

  it "rejects a blank query" do
    get endpoint, params: { query: "   " }

    expect(response).to have_http_status(422)
    expect(json_body.dig("error", "code")).to eq("invalid_query")
  end

  it "returns 404 when the address cannot be resolved" do
    allow(service).to receive(:forecast)
      .and_raise(Weather::WeatherService::AddressNotFoundError)

    get endpoint, params: { query: query }

    expect(response).to have_http_status(:not_found)
    expect(json_body.dig("error", "code")).to eq("address_not_found")
    expect(json_body.dig("error", "message")).to include("could not find an address")
  end

  it "returns 503 when the address lookup service fails" do
    allow(service).to receive(:forecast).and_raise(AddressResolver::Error, "lookup down")

    get endpoint, params: { query: query }

    expect(response).to have_http_status(:service_unavailable)
    expect(json_body.dig("error", "code")).to eq("address_lookup_unavailable")
  end

  it "returns 503 when every weather provider fails" do
    allow(service).to receive(:forecast)
      .and_raise(Weather::WeatherService::AllProvidersFailedError, "all providers down")

    get endpoint, params: { query: query }

    expect(response).to have_http_status(:service_unavailable)
    expect(json_body.dig("error", "code")).to eq("weather_unavailable")
  end

  it "returns 500 for an unexpected failure" do
    allow(service).to receive(:forecast).and_raise(StandardError, "unexpected failure")

    get endpoint, params: { query: query }

    expect(response).to have_http_status(:internal_server_error)
    expect(json_body.dig("error", "code")).to eq("internal_error")
  end
end
