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

    # Restore a previous version by creating a new version with its content.
    # Fires :version_restored (not :version_created). Never mutates existing versions.
    #
    # @param document [Docsmith::Document]
    # @param version [Integer] version_number to restore from
    # @param author [Object, nil]
    # @param config [Hash] resolved config
    # @return [Docsmith::DocumentVersion] the new version
    # @raise [Docsmith::VersionNotFound]
    def self.restore!(document, version:, author:, config: nil)
      config      ||= Configuration.resolve({}, Docsmith.configuration)
      from_version  = document.document_versions.find_by(version_number: version)
      raise VersionNotFound, "Version #{version} not found on this document" unless from_version

      next_num = document.versions_count + 1

      new_version = DocumentVersion.create!(
        document:       document,
        version_number: next_num,
        content:        from_version.content,
        content_type:   document.content_type,
        author:         author,
        change_summary: "Restored from v#{version}",
        metadata:       {}
      )

      document.update_columns(
        content:           from_version.content,
        versions_count:    next_num,
        last_versioned_at: Time.current
      )

      record = document.subject || document
      Events::Notifier.instrument(:version_restored,
        record: record, document: document, version: new_version,
        author: author, from_version: from_version)

      new_version
    end

    # Tag a specific version with a name unique to this document.
    #
    # @param document [Docsmith::Document]
    # @param version [Integer] version_number to tag
    # @param name [String] unique per document
    # @param author [Object, nil]
    # @return [Docsmith::VersionTag]
    # @raise [Docsmith::VersionNotFound]
    # @raise [Docsmith::TagAlreadyExists]
    def self.tag!(document, version:, name:, author:)
      version_record = document.document_versions.find_by(version_number: version)
      raise VersionNotFound, "Version #{version} not found on this document" unless version_record

      if VersionTag.exists?(document_id: document.id, name: name)
        raise TagAlreadyExists, "Tag '#{name}' already exists on this document"
      end

      tag = VersionTag.create!(
        document: document,
        version:  version_record,
        name:     name,
        author:   author
      )

      record = document.subject || document
      Events::Notifier.instrument(:version_tagged,
        record: record, document: document, version: version_record,
        author: author, tag_name: name)

      tag
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
