# frozen_string_literal: true

require "json"

module Docsmith
  module Rendering
    # Renders a DocumentVersion's content as a JSON string.
    # For json content_type: re-parses and pretty-prints.
    # For other types: wraps content in a JSON envelope.
    class JsonRenderer
      # @param version [Docsmith::DocumentVersion]
      # @param options [Hash] unused in Phase 2
      # @return [String] JSON representation of the version content
      def render(version, **options)
        content      = version.content.to_s
        content_type = version.content_type.to_s

        case content_type
        when "json"
          JSON.pretty_generate(JSON.parse(content))
        else
          { content_type: content_type, content: content }.to_json
        end
      rescue JSON::ParserError
        { content_type: content_type, content: content, error: "invalid_json" }.to_json
      end
    end
  end
end
