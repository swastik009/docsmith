# frozen_string_literal: true

require "json"

module Docsmith
  module Comments
    # Represents a comment on a specific DocumentVersion.
    # Supports document-level and range-anchored inline annotations,
    # threaded replies via parent/replies, and resolution tracking.
    class Comment < ActiveRecord::Base
      self.table_name = "docsmith_comments"

      belongs_to :version,     class_name: "Docsmith::DocumentVersion", foreign_key: :version_id
      belongs_to :author,      polymorphic: true, optional: true
      belongs_to :parent,      class_name: "Docsmith::Comments::Comment", optional: true
      belongs_to :resolved_by, polymorphic: true, optional: true
      has_many   :replies,     class_name: "Docsmith::Comments::Comment",
                               foreign_key: :parent_id, dependent: :destroy

      validates :body,        presence: true
      validates :anchor_type, inclusion: { in: %w[document range] }

      scope :top_level,      -> { where(parent_id: nil) }
      scope :unresolved,     -> { where(resolved: false) }
      scope :document_level, -> { where(anchor_type: "document") }
      scope :range_anchored, -> { where(anchor_type: "range") }

      # anchor_data needs no custom accessors: the column is :json everywhere
      # (:jsonb on PostgreSQL), so ActiveRecord casts it to a Hash on read and
      # serializes it on write. The previous hand-rolled pair existed only
      # because the test schema declared the column :text, and it raised an
      # unrescued JSON::ParserError from a plain attribute reader when the
      # stored text was malformed.
      #
      # Assign a Hash, not a JSON String. A String is stored as a JSON string
      # literal and reads back as a String, where the old :text column would
      # have parsed it into a Hash.
    end
  end
end
