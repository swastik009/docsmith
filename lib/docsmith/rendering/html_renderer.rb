# frozen_string_literal: true

require "cgi"
require "json"

module Docsmith
  module Rendering
    # Renders a DocumentVersion's content as an HTML string.
    # Markdown is shown pre-formatted (no external gem dependency).
    # JSON is pretty-printed inside a pre block.
    # html content passes through Docsmith.configuration.html_sanitizer.
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
          sanitize_html(content)
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

      private

      # Stored HTML is untrusted input. Returning it verbatim is stored XSS, so
      # that only happens when the host app explicitly asks for it.
      # See Docsmith::Configuration#html_sanitizer for the three modes.
      #
      # @param content [String] raw stored HTML
      # @return [String]
      def sanitize_html(content)
        sanitizer = Docsmith.configuration.html_sanitizer

        case sanitizer
        when :unsafe_raw       then content
        when nil               then "<pre class=\"docsmith-html\">#{CGI.escapeHTML(content)}</pre>"
        else
          raise Docsmith::InvalidHtmlSanitizer, <<~MSG unless sanitizer.respond_to?(:call)
            html_sanitizer must respond to #call, or be :unsafe_raw or nil.
            Got: #{sanitizer.inspect}
          MSG

          sanitizer.call(content).to_s
        end
      end
    end
  end
end
