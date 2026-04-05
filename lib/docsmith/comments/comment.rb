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

      # Deserializes anchor_data from JSON text (SQLite) or returns hash directly (PostgreSQL jsonb).
      #
      # @return [Hash]
      def anchor_data
        raw = read_attribute(:anchor_data)
        raw.is_a?(String) ? JSON.parse(raw) : raw.to_h
      end

      # Serializes anchor_data as JSON for storage.
      #
      # @param data [Hash, String]
      def anchor_data=(data)
        write_attribute(:anchor_data, data.is_a?(String) ? data : data.to_json)
      end
    end
  end
end
