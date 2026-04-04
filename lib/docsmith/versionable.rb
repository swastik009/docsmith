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

    # Placeholder — implemented in Task 1.17
    def _docsmith_auto_save_callback; end
  end
end
