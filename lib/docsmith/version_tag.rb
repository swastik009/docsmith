# frozen_string_literal: true

module Docsmith
  # Named label on a DocumentVersion.
  # Tag names are unique per document (not per version) — enforced at DB level
  # via the unique index on [document_id, name] in docsmith_version_tags.
  # document_id is denormalized on this table to enable that DB-level constraint.
  class VersionTag < ActiveRecord::Base
    self.table_name = "docsmith_version_tags"

    belongs_to :document,
               class_name:  "Docsmith::Document",
               foreign_key: :document_id
    belongs_to :version,
               class_name:  "Docsmith::DocumentVersion",
               foreign_key: :version_id
    belongs_to :author, polymorphic: true, optional: true

    validates :name,        presence: true
    validates :document_id, presence: true
    validates :version_id,  presence: true
    validates :name, uniqueness: { scope: :document_id,
                                   message: "already exists on this document" }
  end
end
