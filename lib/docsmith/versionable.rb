# frozen_string_literal: true

module Docsmith
  # ActiveRecord mixin that adds full versioning to any model.
  #
  # Usage:
  #   class Article < ApplicationRecord
  #     include Docsmith::Versionable
  #     docsmith_config { content_field :body; content_type :markdown }
  #   end
  module Versionable
    def self.included(base)
      base.extend(ClassMethods)
      base.after_save(:_docsmith_auto_save_callback)
    end

    module ClassMethods
      # Configure per-class Docsmith options. All keys optional.
      # Unset keys fall through to global config then gem defaults.
      # @yield block evaluated on a Docsmith::ClassConfig instance
      # @return [Docsmith::ClassConfig]
      def docsmith_config(&block)
        @_docsmith_class_config ||= Docsmith::ClassConfig.new
        @_docsmith_class_config.instance_eval(&block) if block_given?
        @_docsmith_class_config
      end

      # @return [Hash] fully resolved config (read-time resolution)
      def docsmith_resolved_config
        Docsmith::Configuration.resolve(
          @_docsmith_class_config&.settings || {},
          Docsmith.configuration
        )
      end
    end

    # Create a new DocumentVersion snapshot of this record's content.
    # Returns nil if content is identical to the latest version.
    # Raises Docsmith::InvalidContentField if content_field returns a non-String
    # and no content_extractor is configured.
    #
    # @param author [Object, nil]
    # @param summary [String, nil]
    # @return [Docsmith::DocumentVersion, nil]
    def save_version!(author:, summary: nil)
      _sync_docsmith_content!
      Docsmith::VersionManager.save!(
        _docsmith_document,
        author:  author,
        summary: summary,
        config:  self.class.docsmith_resolved_config
      )
    end

    # Debounced auto-save. Returns nil if debounce window has not elapsed
    # OR content is unchanged. Both non-save cases return nil.
    # auto_save: false in config causes this to always return nil.
    #
    # @param author [Object, nil]
    # @return [Docsmith::DocumentVersion, nil]
    def auto_save_version!(author: nil)
      config = self.class.docsmith_resolved_config
      return nil unless config[:auto_save]

      _sync_docsmith_content!
      Docsmith::AutoSave.call(_docsmith_document, author: author, config: config)
    end

    # @return [ActiveRecord::Relation<Docsmith::DocumentVersion>] ordered by version_number
    def versions
      _docsmith_document.document_versions
    end

    # @return [Docsmith::DocumentVersion, nil] latest version
    def current_version
      _docsmith_document.current_version
    end

    # @param number [Integer] 1-indexed version_number
    # @return [Docsmith::DocumentVersion, nil]
    def version(number)
      _docsmith_document.document_versions.find_by(version_number: number)
    end

    private

    # Finds or creates the shadow Docsmith::Document for this record.
    # Cached in @_docsmith_document after first lookup.
    def _docsmith_document
      config = self.class.docsmith_resolved_config
      @_docsmith_document ||= Docsmith::Document.find_or_create_by!(subject: self) do |doc|
        doc.content_type = config[:content_type].to_s
        doc.title        = respond_to?(:title) ? title.to_s : self.class.name
      end
    end

    # Reads content from the model via content_extractor or content_field,
    # validates it is a String, then syncs to the shadow document's content column.
    def _sync_docsmith_content!
      config = self.class.docsmith_resolved_config

      raw = if config[:content_extractor]
              config[:content_extractor].call(self)
            else
              public_send(config[:content_field])
            end

      unless raw.nil? || raw.is_a?(String)
        source = config[:content_extractor] ? "content_extractor" : "content_field :#{config[:content_field]}"
        raise Docsmith::InvalidContentField,
          "#{source} must return a String, got #{raw.class}. " \
          "Use content_extractor: ->(record) { ... } for non-string fields."
      end

      _docsmith_document.update_column(:content, raw.to_s)
    end

    def _docsmith_auto_save_callback
      auto_save_version!
    rescue Docsmith::InvalidContentField
      # Swallow on auto-save — user must call save_version! explicitly to see the error.
      nil
    end
  end
end
