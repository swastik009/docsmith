# frozen_string_literal: true

module Docsmith
  module Diff
    # Computes diffs between two DocumentVersion records.
    # Uses Renderers::Registry to select the renderer for the content type.
    class Engine
      class << self
        # @param version_a [Docsmith::DocumentVersion] the older version
        # @param version_b [Docsmith::DocumentVersion] the newer version
        # @return [Docsmith::Diff::Result]
        def between(version_a, version_b)
          content_type = version_a.content_type.to_s
          renderer     = Renderers::Registry.for(content_type).new
          changes      = renderer.compute(version_a.content.to_s, version_b.content.to_s)

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
