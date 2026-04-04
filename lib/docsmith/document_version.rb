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
    has_many   :version_tags,
               class_name:  "Docsmith::VersionTag",
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
  end
end
