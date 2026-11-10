module AddressResolution
  # Raised when an address resolver cannot complete a lookup. Controllers rescue
  # AddressResolver::Error, which aliases this class.
  class Error < StandardError; end

  # Raised when ADDRESS_RESOLVER names a provider that is not registered.
  class UnknownResolverError < Error; end
end
