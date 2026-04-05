# frozen_string_literal: true

require "cgi"
require "json"

module Docsmith
  module Rendering
    # Renders a DocumentVersion's content as an HTML string.
    # Markdown is shown pre-formatted (no external gem dependency).
    # JSON is pretty-printed inside a pre block.
    # Subclass and override #render to plug in a markdown gem (e.g. redcarpet).
    class HtmlRenderer
      # @param version [Docsmith::DocumentVersion]
      # @param options [Hash] unused in Phase 2; available for subclasses
      # @return [String] HTML representation of the version content
      def render(version, **options)
        content      = version.content.to_s
        content_type = version.content_type.to_s

        case content_type
        when "html"
          content
        when "markdown"
          "<pre class=\"docsmith-markdown\">#{CGI.escapeHTML(content)}</pre>"
        when "json"
          pretty = JSON.pretty_generate(JSON.parse(content))
          "<pre class=\"docsmith-json\">#{CGI.escapeHTML(pretty)}</pre>"
        else
          "<pre>#{CGI.escapeHTML(content)}</pre>"
        end
      rescue JSON::ParserError
        "<pre>#{CGI.escapeHTML(content)}</pre>"
      end
    end
  end
end
