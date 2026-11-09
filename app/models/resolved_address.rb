# Immutable value object returned by AddressResolver after a successful
# geocoding lookup. Addresses are cached in Redis and are not persisted in
# PostgreSQL.
ResolvedAddress = Data.define(
  :zip_code,
  :country_code,
  :city,
  :region_state,
  :latitude,
  :longitude,
  :timezone,
  :geocoding_source,
  :geocoded_at
)
