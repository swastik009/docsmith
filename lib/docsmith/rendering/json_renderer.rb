# frozen_string_literal: true

require "json"

module Docsmith
  module Rendering
    # Renders a DocumentVersion as a JSON export envelope.
    #
    # One shape for every content_type. Before 0.2.0 this returned two
    # incompatible schemas — a bare pretty-printed document for content_type
    # "json", an envelope for everything else — so no client could parse it
    # generically.
    #
    # "content" is always the exact stored string, byte for byte. This is a
    # versioning gem: an export that re-formatted the snapshot would not match
    # what was versioned, and a client diffing two exports locally would get
    # different results than the gem's own diff.
    #
    # Pass include_parsed: true to additionally receive the parsed document under
    # "data". That is the only code path that parses, so the default export
    # cannot fail on malformed content.
    class JsonRenderer
      # @param version [Docsmith::DocumentVersion]
      # @param include_parsed [Boolean] add "data" with the parsed document (json only)
      # @return [String] JSON representation of the version
      def render(version, include_parsed: false, **_options)
        to_h(version, include_parsed: include_parsed).to_json
      end

      # The canonical envelope, and the single source of truth for its shape.
      #
      # author is emitted as type/id only. The gem cannot know the host app's
      # author class, which fields it exposes, or which of them are personal
      # data, so it never serializes the record itself.
      #
      # @param version [Docsmith::DocumentVersion]
      # @param include_parsed [Boolean]
      # @return [Hash] string-keyed, JSON-ready
      # @raise [Docsmith::InvalidJsonContent] if include_parsed is set and content does not parse
      def to_h(version, include_parsed: false, **_options)
        envelope = {
          "schema_version" => Docsmith::JSON_SCHEMA_VERSION,
          "document_id"    => version.document_id,
          "version_number" => version.version_number,
          "content_type"   => version.content_type.to_s,
          "content"        => version.content.to_s,
          "change_summary" => version.change_summary,
          "author"         => author_for(version),
          "metadata"       => version.metadata,
          "created_at"     => version.created_at&.utc&.iso8601(3)
        }

        return envelope unless include_parsed && envelope["content_type"] == "json"

        envelope.merge("data" => parse(envelope["content"], version))
      end

      private

      # @return [Hash, nil]
      def author_for(version)
        return nil if version.author_type.nil? && version.author_id.nil?

        { "type" => version.author_type, "id" => version.author_id }
      end

      def parse(content, version)
        JSON.parse(content)
      rescue JSON::ParserError => e
        raise Docsmith::InvalidJsonContent,
              "version #{version.version_number} of document #{version.document_id} " \
              "has content_type \"json\" but its content does not parse: #{e.message}"
      end
    end
  end
end
