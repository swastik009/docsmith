# frozen_string_literal: true

module Docsmith
  module Branches
    # Represents a named branch of a document's version history.
    # Branches fork from source_version and accumulate versions independently.
    # On merge, a new version is created on the main document history.
    class Branch < ActiveRecord::Base
      self.table_name = "docsmith_branches"

      STATUSES = %w[active merged abandoned].freeze

      belongs_to :document,       class_name: "Docsmith::Document"
      belongs_to :source_version, class_name: "Docsmith::DocumentVersion", foreign_key: :source_version_id
      belongs_to :head_version,   class_name: "Docsmith::DocumentVersion", foreign_key: :head_version_id, optional: true
      belongs_to :author,         polymorphic: true, optional: true

      validates :name,   presence: true
      validates :status, inclusion: { in: STATUSES }

      scope :active,    -> { where(status: "active") }
      scope :merged,    -> { where(status: "merged") }
      scope :abandoned, -> { where(status: "abandoned") }

      # Returns all DocumentVersions on this branch.
      #
      # @return [ActiveRecord::Relation<Docsmith::DocumentVersion>]
      def versions
        Docsmith::DocumentVersion.where(branch_id: id).order(:version_number)
      end

      # Returns the latest version on this branch (head_version association).
      #
      # @return [Docsmith::DocumentVersion, nil]
      def head
        head_version
      end

      # Computes a diff between the source_version (fork point) and the branch head.
      #
      # @return [Docsmith::Diff::Result, nil] nil if branch has no versions yet
      def diff_from_source
        return nil unless head_version

        Docsmith::Diff.between(source_version, head_version)
      end

      # Computes a diff between the branch head and the current main head.
      #
      # @return [Docsmith::Diff::Result, nil] nil if branch has no versions yet
      def diff_against_current
        return nil unless head_version

        main_head = document.document_versions.where(branch_id: nil).order(version_number: :desc).first
        return nil unless main_head

        Docsmith::Diff.between(head_version, main_head)
      end
    end
  end
end
