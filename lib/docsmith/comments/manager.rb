# frozen_string_literal: true

module Docsmith
  module Comments
    # Service object for creating and resolving comments on document versions.
    class Manager
      class << self
        # Adds a comment to a specific version of a document.
        #
        # @param document [Docsmith::Document]
        # @param version_number [Integer]
        # @param body [String]
        # @param author [Object] polymorphic author record
        # @param anchor [Hash, nil] { start_offset:, end_offset: } for inline range comments
        # @param parent [Comments::Comment, nil] parent comment for threading
        # @return [Comments::Comment]
        # @raise [ActiveRecord::RecordNotFound] if version_number does not exist
        def add!(document, version_number:, body:, author:, anchor: nil, parent: nil)
          version = Docsmith::DocumentVersion.find_by!(document: document, version_number: version_number)

          anchor_type = anchor ? "range" : "document"
          anchor_data = if anchor
                          Anchor.build(version.content.to_s,
                                       start_offset: anchor[:start_offset],
                                       end_offset:   anchor[:end_offset])
                        else
                          {}
                        end

          comment = Comment.create!(
            version:     version,
            author:      author,
            body:        body,
            anchor_type: anchor_type,
            anchor_data: anchor_data,
            parent:      parent,
            resolved:    false
          )

          Events::Notifier.instrument(:comment_added,
            record:   document.subject || document,
            document: document,
            version:  version,
            author:   author,
            comment:  comment
          )

          comment
        end

        # Marks a comment as resolved.
        #
        # @param comment [Comments::Comment]
        # @param by [Object] polymorphic resolver record
        # @return [Comments::Comment]
        def resolve!(comment, by:)
          comment.update!(resolved: true, resolved_by: by, resolved_at: Time.current)

          document = comment.version.document
          Events::Notifier.instrument(:comment_resolved,
            record:   document.subject || document,
            document: document,
            version:  comment.version,
            author:   by,
            comment:  comment
          )

          comment
        end
      end
    end
  end
end
