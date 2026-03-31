# frozen_string_literal: true

require "digest"

module Docsmith
  module Comments
    # Builds and migrates range anchors for inline comments.
    # An anchor captures character offsets and a content hash of the selected text
    # so the comment can be relocated when content changes between versions.
    module Anchor
      ACTIVE   = "active"
      DRIFTED  = "drifted"
      ORPHANED = "orphaned"

      # Builds anchor_data for a new range comment.
      #
      # @param content [String] the version content at comment time
      # @param start_offset [Integer] character offset of selection start (inclusive)
      # @param end_offset [Integer] character offset of selection end (exclusive)
      # @return [Hash] anchor_data hash ready to store on the Comment
      def self.build(content, start_offset:, end_offset:)
        anchored_text = content[start_offset...end_offset].to_s
        {
          start_offset:  start_offset,
          end_offset:    end_offset,
          content_hash:  Digest::SHA256.hexdigest(anchored_text),
          anchored_text: anchored_text,
          status:        ACTIVE
        }
      end

      # Attempts to migrate an existing anchor to new version content.
      #
      # Strategy:
      # 1. Try exact offset — if SHA256 of text at same offsets matches, return ACTIVE.
      # 2. Search the full content for the original anchored text — return DRIFTED with new offsets.
      # 3. If not found anywhere, return ORPHANED.
      #
      # @param content [String] new version content
      # @param anchor_data [Hash] existing anchor_data (string keys from JSON storage)
      # @return [Hash] updated anchor_data with new :status
      def self.migrate(content, anchor_data)
        start_off     = anchor_data["start_offset"]
        end_off       = anchor_data["end_offset"]
        original_hash = anchor_data["content_hash"]
        original_text = anchor_data["anchored_text"]

        # 1. Exact offset check
        candidate = content[start_off...end_off].to_s
        return anchor_data.merge("status" => ACTIVE) if Digest::SHA256.hexdigest(candidate) == original_hash

        # 2. Full-text search for relocated text
        idx = content.index(original_text)
        if idx
          new_end = idx + original_text.length
          return anchor_data.merge(
            "start_offset" => idx,
            "end_offset"   => new_end,
            "status"       => DRIFTED
          )
        end

        # 3. Orphaned — text no longer exists
        anchor_data.merge("status" => ORPHANED)
      end
    end
  end
end
