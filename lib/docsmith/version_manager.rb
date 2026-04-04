# frozen_string_literal: true

module Docsmith
  # Service object for all version lifecycle operations.
  # The Versionable mixin delegates here after resolving the shadow document.
  # Always receives a Docsmith::Document instance.
  module VersionManager
    # Create a new DocumentVersion snapshot.
    # Returns nil if content is identical to the latest version (string == check).
    #
    # @param document [Docsmith::Document]
    # @param author [Object, nil]
    # @param summary [String, nil]
    # @param config [Hash] resolved config
    # @return [Docsmith::DocumentVersion, nil]
    def self.save!(document, author:, summary: nil, config: nil)
      config  ||= Configuration.resolve({}, Docsmith.configuration)
      current   = document.content.to_s
      latest    = document.document_versions.last

      return nil if latest && latest.content == current

      next_num = document.versions_count + 1

      version = DocumentVersion.create!(
        document:       document,
        version_number: next_num,
        content:        current,
        content_type:   document.content_type,
        author:         author,
        change_summary: summary,
        metadata:       {}
      )

      document.update_columns(
        versions_count:    next_num,
        last_versioned_at: Time.current
      )
      document.versions_count = next_num

      prune_if_needed!(document, version, config) if config[:max_versions]

      record = document.subject || document
      Events::Notifier.instrument(:version_created,
        record: record, document: document, version: version, author: author)

      version
    end

    def self.prune_if_needed!(document, new_version, config)
      max = config[:max_versions]
      return unless max && document.versions_count > max

      tagged_ids      = VersionTag.where(document_id: document.id).select(:version_id)
      oldest_untagged = document.document_versions
                                .where.not(id: tagged_ids)
                                .where.not(id: new_version.id)
                                .first

      unless oldest_untagged
        raise MaxVersionsExceeded,
          "All #{document.versions_count} versions are tagged. Cannot prune to stay within " \
          "max_versions: #{max}. Remove a tag or increase max_versions."
      end

      oldest_untagged.destroy!
      document.update_column(:versions_count, document.versions_count - 1)
    end
    private_class_method :prune_if_needed!
  end
end
