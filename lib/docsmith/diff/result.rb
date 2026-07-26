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
      # Grouped edits produced by Renderers::Base#compute. Symbol-keyed mirror of
      # the serialized form: each entry is
      # { type: :insert|:delete|:replace, old: {...span}, new: {...span} }
      # where a span is { start:, end:, line:, column:, text: }.
      #
      # @return [Array<Hash>]
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

      # @return [Integer] number of pure insertions
      def insertions
        changes.count { |c| c[:type] == :insert }
      end

      # @return [Integer] number of pure deletions
      def deletions
        changes.count { |c| c[:type] == :delete }
      end

      # @return [Integer] number of replacements (an old span became a new one)
      def replacements
        changes.count { |c| c[:type] == :replace }
      end

      # Edit counts by kind. insertions and deletions are pure; a replacement is
      # counted once rather than as one of each, so a rewritten document never
      # reports 0/0 alongside a non-empty changes array. For git-style totals, add
      # replacements to either side.
      #
      # @return [Hash] string-keyed counts
      def stats
        {
          "insertions"   => insertions,
          "deletions"    => deletions,
          "replacements" => replacements,
          "total"        => changes.length
        }
      end

      # @return [String] HTML diff representation
      def to_html
        Renderers::Registry.for(content_type).new.render_html(changes)
      end

      # The canonical JSON representation, and the single source of truth for it.
      #
      # Defining as_json is what makes nesting work: ActiveSupport calls it for
      # `render json: { diff: result }`, `[result].to_json`, and JSON.generate.
      # Without it those fell through to Object#as_json (instance_values), which
      # silently dropped "stats" and emitted "line" instead of "position".
      #
      # @param options [Hash, nil] accepted for API compatibility; unused
      # @return [Hash] string-keyed, JSON-ready
      def as_json(options = nil) # rubocop:disable Lint/UnusedMethodArgument
        {
          "schema_version" => Docsmith::JSON_SCHEMA_VERSION,
          "content_type"   => content_type,
          "from_version"   => from_version,
          "to_version"     => to_version,
          "stats"          => stats,
          "changes"        => changes.map { |c| serialize_change(c) }
        }
      end

      # Args are forwarded so JSON.pretty_generate indents a nested Result
      # instead of splicing it in as one compact line.
      #
      # @return [String] JSON diff representation matching the documented schema
      def to_json(*args)
        as_json.to_json(*args)
      end

      private

      # Every edit serializes to the same keys, and the two sides never share a
      # coordinate space. An absent side is a zero-width span marking the point
      # where text was inserted into, or removed from, that document.
      def serialize_change(change)
        {
          "type" => change[:type].to_s,
          "old"  => serialize_span(change[:old]),
          "new"  => serialize_span(change[:new])
        }
      end

      def serialize_span(span)
        {
          "start"  => span[:start],
          "end"    => span[:end],
          "line"   => span[:line],
          "column" => span[:column],
          "text"   => span[:text]
        }
      end
    end
  end
end
