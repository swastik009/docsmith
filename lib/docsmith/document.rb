# frozen_string_literal: true

module Docsmith
  # AR model backed by docsmith_documents.
  # Serves as both a standalone versioned document and the shadow record
  # auto-created when Docsmith::Versionable is included on any AR model.
  #
  # Shadow record lifecycle:
  #   include Docsmith::Versionable on Article → first save_version! call does:
  #     Docsmith::Document.find_or_create_by!(subject: article_instance)
  #   subject_type / subject_id link back to the originating record.
  class Document < ActiveRecord::Base
    self.table_name = "docsmith_documents"

    belongs_to :subject, polymorphic: true, optional: true
    has_many :document_versions,
             -> { order(:version_number) },
             foreign_key: :document_id,
             class_name:  "Docsmith::DocumentVersion",
             dependent:   :destroy
    has_many :version_tags,
             through:    :document_versions,
             class_name: "Docsmith::VersionTag"

    validates :content_type, presence: true,
              inclusion: { in: %w[html markdown json] }

    # @return [Docsmith::DocumentVersion, nil] latest version by version_number
    def current_version
      document_versions.last
    rescue NameError
      nil
    end

    # Find or create the shadow Document for an existing AR record.
    # @param record [ActiveRecord::Base]
    # @param field [Symbol, nil] ignored — content_field comes from class config
    # @return [Docsmith::Document]
    def self.from_record(record, field: nil)
      find_or_create_by!(subject: record) do |doc|
        doc.content_type = "markdown"
        doc.title = record.respond_to?(:title) ? record.title.to_s : record.class.name
      end
    end
  end
end
