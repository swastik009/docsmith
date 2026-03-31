# frozen_string_literal: true

module Docsmith
  # Applies debounce logic before delegating to VersionManager.save!
  # Extracted for independent testability.
  module AutoSave
    # @param document [Docsmith::Document]
    # @param author [Object, nil]
    # @param config [Hash] resolved config
    # @return [Docsmith::DocumentVersion, nil] nil if within debounce or content unchanged
    def self.call(document, author:, config:)
      return nil if within_debounce?(document, config)

      VersionManager.save!(document, author: author, config: config)
    end

    # Returns true if the debounce window has not yet elapsed.
    # Public so specs can assert on timing logic without mocking Time.
    # @param document [Docsmith::Document]
    # @param config [Hash] resolved config
    # @return [Boolean]
    def self.within_debounce?(document, config)
      last_saved = document.last_versioned_at
      return false if last_saved.nil?

      Time.current < last_saved + config[:debounce].to_i
    end
  end
end
