require "rails_helper"

RSpec.describe WeatherHelper, type: :helper do
  describe "#weather_location_name" do
    it "joins the available location fields" do
      expect(weather_location_name(city: "Daytona Beach", postal_code: "32114"))
        .to eq("Daytona Beach, 32114")
    end

    it "falls back when the location has no fields" do
      expect(weather_location_name({})).to eq("Selected location")
    end
  end

  describe "#weather_coordinates" do
    it "formats coordinates" do
      expect(weather_coordinates(latitude: 1.23456, longitude: 2.34567)).to eq("1.2346, 2.3457")
    end

    it "handles missing coordinates" do
      expect(weather_coordinates({})).to eq("—")
    end
  end

  describe "#weather_source_name" do
    it "maps known and unknown provider names" do
      expect(weather_source_name("open_meteo")).to eq("Open-Meteo")
      expect(weather_source_name("custom_provider")).to eq("Custom provider")
    end
  end

  describe "#weather_measurement" do
    it "formats numeric values and handles missing values" do
      expect(weather_measurement(12.34, "°C")).to eq("12.3 °C")
      expect(weather_measurement(nil, "°C")).to eq("—")
    end
  end

  describe "#weather_wind" do
    it "combines speed and direction" do
      expect(weather_wind(3.5, 90)).to eq("3.5 m/s 90°")
    end

    it "handles missing wind data" do
      expect(weather_wind(nil, nil)).to eq("—")
    end
  end

  describe "#weather_time" do
    it "formats a timestamp in the requested time zone" do
      expect(weather_time("2026-11-04T12:00:00Z", "America/New_York")).to eq("Wed, Nov 4 2026, 7:00 EST")
    end

    it "handles blank and invalid timestamps" do
      expect(weather_time(nil)).to eq("—")
      expect(weather_time("not a time")).to eq("not a time")
      expect(weather_time("25:99")).to eq("25:99")
    end
  end

  describe "#weather_date" do
    it "formats a date" do
      expect(weather_date("2026-11-04")).to eq("Wed, Nov 4")
    end

    it "handles blank and invalid dates" do
      expect(weather_date(nil)).to eq("—")
      expect(weather_date("not a date")).to eq("not a date")
    end
  end
end
