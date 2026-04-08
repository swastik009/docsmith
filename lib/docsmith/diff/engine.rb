# frozen_string_literal: true

module Docsmith
  module Diff
    # Computes diffs between two DocumentVersion records.
    # For markdown and html content types, a format-aware parser is used
    # (word-level for markdown, tag-atomic for html).
    # Falls back to Renderers::Base (line-level) for json and unknown types.
    class Engine
      PARSERS = {
        "markdown" => Parsers::Markdown,
        "html"     => Parsers::Html
      }.freeze

      class << self
        # @param version_a [Docsmith::DocumentVersion] the older version
        # @param version_b [Docsmith::DocumentVersion] the newer version
        # @return [Docsmith::Diff::Result]
        def between(version_a, version_b)
          content_type = version_a.content_type.to_s
          parser       = PARSERS.fetch(content_type, Renderers::Base).new
          changes      = parser.compute(version_a.content.to_s, version_b.content.to_s)

          Result.new(
            content_type: content_type,
            from_version: version_a.version_number,
            to_version:   version_b.version_number,
            changes:      changes
          )
        end
      end
    end

    # Convenience module method: Docsmith::Diff.between(v1, v2)
    def self.between(version_a, version_b)
      Engine.between(version_a, version_b)
    end
  end
end
