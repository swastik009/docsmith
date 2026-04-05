# frozen_string_literal: true

require "json"

module Docsmith
  module Diff
    # Holds the computed diff between two DocumentVersion records.
    # Produced by Diff::Engine.between; consumed by callers for stats and rendering.
    class Result
      # @return [String] content type of the diffed document ("markdown", "html", "json")
      attr_reader :content_type
      # @return [Integer] version_number of the from (older) version
      attr_reader :from_version
      # @return [Integer] version_number of the to (newer) version
      attr_reader :to_version
      # @return [Array<Hash>] change hashes produced by Renderers::Base#compute
      attr_reader :changes

      # @param content_type [String]
      # @param from_version [Integer]
      # @param to_version [Integer]
      # @param changes [Array<Hash>]
      def initialize(content_type:, from_version:, to_version:, changes:)
        @content_type = content_type
        @from_version = from_version
        @to_version   = to_version
        @changes      = changes
      end

      # @return [Integer] number of added lines
      def additions
        changes.count { |c| c[:type] == :addition }
      end

      # @return [Integer] number of deleted lines
      def deletions
        changes.count { |c| c[:type] == :deletion }
      end

      # @return [String] HTML diff representation
      def to_html
        Renderers::Registry.for(content_type).new.render_html(changes)
      end

      # @return [String] JSON diff representation matching the documented schema
      def to_json(*)
        {
          content_type: content_type,
          from_version: from_version,
          to_version:   to_version,
          stats:        { additions: additions, deletions: deletions },
          changes:      changes.map { |c| serialize_change(c) }
        }.to_json
      end

      private

      def serialize_change(change)
        case change[:type]
        when :addition
          { type: "addition", position: { line: change[:line] }, content: change[:content] }
        when :deletion
          { type: "deletion", position: { line: change[:line] }, content: change[:content] }
        when :modification
          {
            type:        "modification",
            position:    { line: change[:line] },
            old_content: change[:old_content],
            new_content: change[:new_content]
          }
        else
          change.transform_keys(&:to_s)
        end
      end
    end
  end
end
