# Forecast App

A small Rails weather application. Enter a street address or ZIP/postal code and the app resolves it with OpenStreetMap Nominatim, Photon, or Open-Meteo Geocoding, then shows current, hourly, and daily conditions from Open-Meteo or NOAA.

The forecast is displayed in a responsive Bootstrap card with a green **Cached** badge or an amber **New request** badge.

A versioned JSON API serves the same forecast data at `GET /api/v1/forecasts`.

## JSON API

Request a forecast with a free-form address or ZIP/postal code:

```bash
curl --get "http://localhost:3000/api/v1/forecasts" \
  --data-urlencode "query=1801 West International Speedway Blvd, Daytona Beach, Florida, United States 32114"
```

Successful responses use a `data` envelope:

```json
{
  "data": {
    "location": {
      "city": "Daytona Beach",
      "region": "Florida",
      "postal_code": "32114",
      "country": "US",
      "timezone": "America/New_York",
      "latitude": 29.1858,
      "longitude": -81.07
    },
    "current": {
      "time": "2026-11-04T12:00:00Z",
      "condition": "Sunny",
      "temperature_c": 25.0
    },
    "hourly": [],
    "daily": [],
    "sources": [ "noaa", "open_meteo" ],
    "provider_errors": {},
    "generated_at": "2026-11-04T12:00:00Z",
    "cache_hit": true
  }
}
```

Optional sections are always present: `hourly` and `daily` are arrays,
`provider_errors` and `location` are objects, and `current` may be `null`.

Errors use an `error` envelope with a stable code:

```json
{
  "error": {
    "code": "address_not_found",
    "message": "We could not find an address or ZIP/postal code matching ..."
  }
}
```

| Condition | Status | Code |
| --- | --- | --- |
| Missing or blank `query` | `422` | `invalid_query` |
| Address not found | `404` | `address_not_found` |
| Address resolver unavailable | `503` | `address_lookup_unavailable` |
| All weather providers failed | `503` | `weather_unavailable` |
| Unexpected failure | `500` | `internal_error` |

Alternatively there is a HTML interface available at `/` and `/weather`.

## Ruby version

- Ruby 3.4.12
- Rails 8.1.4

## System dependencies

- Ruby 3.4.12
- PostgreSQL 17
- Redis 7+ or Valkey 8
- libpq-dev
- Docker + Docker Compose

## Configuration

Configuration is environment-variable driven:

| Variable | Default | Purpose |
| --- | --- | --- |
| `DATABASE_URL` | Built from `config/database.yml` | PostgreSQL connection |
| `REDIS_URL` | `redis://localhost:6379/0` | `Rails.cache` connection |
| `RAILS_MAX_THREADS` | `5` | Database pool size |
| `WEATHER_PROVIDERS` | `noaa,open_meteo` | Comma-separated provider list |
| `WEATHER_USER_AGENT` | `ForecastApp/1.0 (weather forecast application)` | Outbound HTTP User-Agent |
| `ADDRESS_RESOLVER` | `nominatim` | Active address resolver: `nominatim`, `photon`, or `open_meteo` |
| `NOMINATIM_URL` | `https://nominatim.openstreetmap.org` | Nominatim base URL |
| `NOMINATIM_USER_AGENT` | Value of `WEATHER_USER_AGENT` | Nominatim User-Agent |
| `PHOTON_URL` | `https://photon.komoot.io` | Photon base URL (point at a self-hosted instance for higher traffic) |
| `PHOTON_USER_AGENT` | Value of `WEATHER_USER_AGENT` | Photon User-Agent |
| `OPEN_METEO_GEOCODING_URL` | `https://geocoding-api.open-meteo.com` | Open-Meteo Geocoding base URL |
| `OPEN_METEO_GEOCODING_USER_AGENT` | Value of `WEATHER_USER_AGENT` | Open-Meteo Geocoding User-Agent |

`Rails.cache` uses Redis in development, test, and production, with separate namespaces:

- `forecast_app:cache:development`
- `forecast_app:cache:test`
- `forecast_app:cache:production`

Forecast responses expire after **30 minutes**. Successful address lookups expire after **30 days**. Both cache paths use a 10-second `race_condition_ttl` so an expiring entry can be served while one process refreshes it, reducing cache stampedes.

Set a descriptive `NOMINATIM_USER_AGENT` that identifies your deployment and a real contact email or URL before using the application in production. Nominatim rejects placeholder contact domains such as `example.com` with HTTP 403.

When a free-form query returns no match, the Nominatim resolver retries once without a recognized country name. Nominatim requests are limited to at most one per second, and the application displays the required OpenStreetMap attribution in its footer.

### Address resolvers

Nominatim remains the default. Select exactly one resolver per deployment with
`ADDRESS_RESOLVER`. The value is validated at boot, so an unknown name fails
fast instead of silently falling back.

| `ADDRESS_RESOLVER` | Provider | Notes |
| --- | --- | --- |
| `nominatim` (default) | [OpenStreetMap Nominatim](https://nominatim.org/) | Full street-address support. One request per second. Requires a valid User-Agent. |
| `photon` | [Photon](https://github.com/komoot/photon), operated by komoot | Full street-address support. The public instance is for light use; self-host for production traffic. One request per second. |
| `open_meteo` | [Open-Meteo Geocoding](https://open-meteo.com/en/docs/geocoding-api) | City and postal-code search only. Full street addresses usually return no result. About ten requests per second. |

Aliases are accepted and normalized: `osm`, `openstreetmap`, and
`open_street_map` map to `nominatim`; `komoot` maps to `photon`; `open-meteo`,
`openmeteo`, and `geocoding` map to `open_meteo`.

```bash
# Default: OpenStreetMap Nominatim
ADDRESS_RESOLVER=nominatim bin/rails server

# Photon, including a self-hosted instance
ADDRESS_RESOLVER=photon \
PHOTON_URL=https://photon.example.com \
bin/rails server

# Open-Meteo Geocoding (best for city or ZIP/postal-code searches)
ADDRESS_RESOLVER=open_meteo bin/rails server

# Docker Compose forwards the resolver variables from your shell
ADDRESS_RESOLVER=photon PHOTON_URL=https://photon.example.com docker compose up
```

Cache keys include the provider name, such as
`address_resolver:photon:v1:<digest>`, so switching resolvers never reuses
another provider's cached result. Only successful lookups are cached.

Provider attribution: Nominatim and Photon use OpenStreetMap data, which
requires attribution to OpenStreetMap contributors. Open-Meteo Geocoding is
based on GeoNames data. Review each provider's usage policy before deploying.

The full behavior is covered by WebMock-backed specs in
`spec/services/address_resolution/`. No live geocoding request is made by the
test suite.

## Database creation

The Docker Compose stack creates the development database automatically from `POSTGRES_DB: forecast-app_development` in `compose.yml`.

To use a local PostgreSQL server instead, create the databases:

```bash
createuser --createdb postgres
createdb -O postgres forecast-app_development
createdb -O postgres forecast-app_test
```

Or point the app at any PostgreSQL instance:

```bash
export DATABASE_URL=postgres://postgres:postgres@localhost:5432/forecast-app_development
```

`config/database.yml` defaults to host `db`, user `postgres`, password `postgres`, and databases `forecast-app_development` and `forecast-app_test`.Override the host with `DATABASE_URL` when running outside Docker.

## Database initialization

Create the schema and run migrations:

```bash
bin/rails db:prepare
```

`db:prepare` creates the database if needed, loads `db/schema.rb`, and runs any pending migrations. It is safe to run repeatedly.

The full setup script performs dependency installation, database preparation, log cleanup, and starts the development server:

```bash
bin/setup
```

Skip the server with `bin/setup --skip-server`.

Seeds are currently empty, but the standard task is available:

```bash
bin/rails db:seed
```

## How to run the test suite

The suite uses RSpec. External HTTP calls to Nominatim, Photon, Open-Meteo Geocoding, NOAA, and Open-Meteo are stubbed with WebMock, so tests never make live requests.

The test environment needs PostgreSQL and Redis:

```bash
docker compose up -d db redis
```

Prepare the test database and run the suite:

```bash
RAILS_ENV=test bin/rails db:prepare
bundle exec rspec
```

`DATABASE_URL` and `REDIS_URL` are respected, so CI or a containerized setup can point the suite at separate services:

```bash
DATABASE_URL=postgres://postgres:postgres@localhost:5432/forecast_app_test \
REDIS_URL=redis://localhost:6379/0 \
bundle exec rspec
```

Coverage is enforced at **100% line coverage** by SimpleCov.

Run the full local CI pipeline (setup, style, security, tests) with:

```bash
bin/ci
```

Or run the checks individually:

```bash
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit check --update
bin/importmap audit
```

GitHub Actions runs the RSpec suite, RuboCop, Brakeman, Bundler Audit, and the importmap audit on pull requests and on pushes to `main`, `development`, and `develop`. The test job starts PostgreSQL and Redis service containers.

## Services (job queues, cache servers, search engines, etc.)

| Service | Used for |
| --- | --- |
| PostgreSQL | ActiveRecord database and test database |
| Redis / Valkey | `Rails.cache` for forecasts and address lookups |
| Nominatim, Photon, or Open-Meteo Geocoding | Configurable address and ZIP/postal-code resolution (`ADDRESS_RESOLVER`) |
| NOAA | Primary weather provider |
| Open-Meteo | Fallback/secondary weather provider |

- **Cache server:** Redis is required in every environment, including tests. Forecast entries expire after 30 minutes; address lookups after 30 days.
- **Outbound HTTP:** `AddressResolver` and the weather providers make HTTPS requests.

## Running with Docker

### Requirements

- Docker
- Docker Compose

### First start

On the project directory. Build and start the containers:

```bash
docker compose up --build
```

This will:

- Build the Rails application container.
- Start PostgreSQL and Redis.
- Install Ruby dependencies.
- Prepare the database.
- Start the Rails server.

Open the application at:

http://localhost:3000

### Subsequent uses

Start the application:

```bash
docker compose up
```

Stop the application:

```bash
docker compose down
```

### Notes

- Application files are stored locally and shared with the container.
- PostgreSQL data is persisted in a Docker volume.
- Redis cache data is persisted in a Docker volume.
- Stopping containers does not delete the database or the cache.
- To rebuild the application image after Dockerfile changes, run:

```bash
docker compose up --build
```

## Weather data

The weather feature is organized as service objects under `app/services`:

- `AddressResolver` resolves a user-entered address through the configured
  geocoding provider and returns an immutable `ResolvedAddress` value object
  with coordinates and postal code. The provider is selected with
  `ADDRESS_RESOLVER`.
- `AddressResolution::{Nominatim,Photon,OpenMeteo}` implement the provider
  adapters, and `AddressResolution::Factory` builds the configured one.
- `Weather::WeatherService` resolves the address, asks the configured providers
  for a forecast, combines their results, and caches the response.
- `Weather::ProviderFactory` builds the configured provider strategies.
- `Weather::Normalizer` maps each provider's response to the common format.
- `Weather::Providers::Base` defines the provider adapter interface.
- `Weather::Providers::Noaa` and `Weather::Providers::OpenMeteo` implement it.

Forecasts and observations are **not** ActiveRecord models. Normalized forecast responses and address lookups are stored only in `Rails.cache`, which uses Redis in development, test, and production with an environment-specific namespace. Resolved addresses are returned as `ResolvedAddress` value objects and are not written to PostgreSQL.

### Units

All provider responses are normalized to metric units before caching:

- Temperature: °C
- Wind speed: m/s
- Precipitation: mm
- Pressure: hPa
- Visibility: km

Convert values to US customary units only in the presentation layer when needed.

### CLI Usage

```ruby
resolver = AddressResolver.new
address = resolver.resolve(
  "1801 West International Speedway Blvd, Daytona Beach, Florida, United States 32114"
)

forecast = Weather::WeatherService.new.forecast(address)
forecast[:current]   # current conditions in metric units
forecast[:hourly]    # hourly forecast entries
forecast[:daily]     # daily forecast entries
forecast[:sources]   # providers that contributed to the response
```
