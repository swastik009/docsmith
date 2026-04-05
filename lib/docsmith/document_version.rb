# frozen_string_literal: true

module Docsmith
  # Immutable content snapshot. Table is docsmith_versions.
  # Class name is DocumentVersion (not Version) to avoid colliding with
  # lib/docsmith/version.rb which holds the Docsmith::VERSION constant.
  class DocumentVersion < ActiveRecord::Base
    self.table_name = "docsmith_versions"

    belongs_to :document,
               class_name:  "Docsmith::Document",
               foreign_key: :document_id
    belongs_to :author, polymorphic: true, optional: true
    belongs_to :branch, class_name: "Docsmith::Branches::Branch", optional: true
    has_many   :version_tags,
               class_name:  "Docsmith::VersionTag",
               foreign_key: :version_id,
               dependent:   :destroy
    has_many :comments,
             class_name:  "Docsmith::Comments::Comment",
             foreign_key: :version_id,
             dependent:   :destroy

    validates :version_number, presence: true,
              uniqueness: { scope: :document_id }
    validates :content,      presence: true
    validates :content_type, presence: true,
              inclusion: { in: %w[html markdown json] }

    # @return [Docsmith::DocumentVersion, nil]
    def previous_version
      document.document_versions
              .where("version_number < ?", version_number)
              .last
    end

    # Renders this version's content in the given output format.
    #
    # @param format [Symbol] :html or :json
    # @param options [Hash] passed through to the renderer
    # @return [String]
    # @raise [ArgumentError] for unknown formats
    def render(format, **options)
      case format.to_sym
      when :html then Rendering::HtmlRenderer.new.render(self, **options)
      when :json then Rendering::JsonRenderer.new.render(self, **options)
      else raise ArgumentError, "Unknown render format: #{format}. Supported: :html, :json"
      end
    end
  end
end
