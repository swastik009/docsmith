# frozen_string_literal: true

module Docsmith
  VERSION = "0.2.0"

  # Wire-format version for every JSON export the gem produces, emitted as the
  # "schema_version" key. Independent of VERSION: it changes only when the shape
  # of an export changes, so third-party clients can branch on it instead of
  # sniffing for keys or pinning a gem version.
  JSON_SCHEMA_VERSION = 1
end
