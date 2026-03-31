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
end
