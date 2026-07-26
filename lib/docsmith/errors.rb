# frozen_string_literal: true

module Docsmith
  # Base class for all Docsmith errors.
  class Error < StandardError; end

  # Raised when content_field returns a non-String and no content_extractor is configured.
  class InvalidContentField < Error; end

  # Raised when max_versions is set, all versions are tagged, and a new version would exceed the limit.
  class MaxVersionsExceeded < Error; end

  # Raised when a requested version_number does not exist on the document.
  class VersionNotFound < Error; end

  # Raised when tag_version! is called with a name already used on this document.
  class TagAlreadyExists < Error; end

  # Raised when a JSON export is asked to parse content (include_parsed: true)
  # on a version whose content_type is "json" but whose content is not valid JSON.
  # The default export path never parses, so it never raises this.
  class InvalidJsonContent < Error; end

  # Raised when configuration.html_sanitizer is neither nil, :unsafe_raw, nor callable.
  # Fails loudly rather than falling back, so a misconfigured sanitizer can never
  # silently degrade into rendering untrusted HTML verbatim.
  class InvalidHtmlSanitizer < Error; end
end
