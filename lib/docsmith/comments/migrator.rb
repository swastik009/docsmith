# frozen_string_literal: true

module Docsmith
  module Comments
    # Migrates top-level comments from one version to another.
    # Document-level comments are copied as-is.
    # Range-anchored comments are re-anchored using Anchor.migrate;
    # orphaned comments fire the :comment_orphaned event.
    class Migrator
      class << self
        # @param document [Docsmith::Document]
        # @param from [Integer] source version_number
        # @param to [Integer] target version_number
        # @return [void]
        def migrate!(document, from:, to:)
          from_version = Docsmith::DocumentVersion.find_by!(document: document, version_number: from)
          to_version   = Docsmith::DocumentVersion.find_by!(document: document, version_number: to)
          new_content  = to_version.content.to_s

          from_version.comments.top_level.each do |comment|
            new_anchor_data = migrate_anchor(comment, new_content)

            new_comment = Comment.create!(
              version:          to_version,
              author_type:      comment.author_type,
              author_id:        comment.author_id,
              body:             comment.body,
              anchor_type:      comment.anchor_type,
              anchor_data:      new_anchor_data,
              resolved:         comment.resolved,
              resolved_by_type: comment.resolved_by_type,
              resolved_by_id:   comment.resolved_by_id,
              resolved_at:      comment.resolved_at
            )

            if orphaned?(comment, new_anchor_data)
              Events::Notifier.instrument(:comment_orphaned,
                record:   document.subject || document,
                document: document,
                version:  to_version,
                author:   nil,
                comment:  new_comment
              )
            end
          end
        end

        private

        # @return [Hash] migrated anchor_data
        def migrate_anchor(comment, new_content)
          return comment.anchor_data if comment.anchor_type == "document"

          Anchor.migrate(new_content, comment.anchor_data)
        end

        # @return [Boolean]
        def orphaned?(comment, new_anchor_data)
          comment.anchor_type == "range" && new_anchor_data["status"] == Anchor::ORPHANED
        end
      end
    end
  end
end
