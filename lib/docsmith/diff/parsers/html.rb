# frozen_string_literal: true

require "diff/lcs"

module Docsmith
  module Diff
    module Parsers
      # HTML-aware diff parser for HTML documents.
      #
      # Tokenizes HTML so that each tag (including its attributes) is one atomic
      # unit and text words are separate units. This prevents the diff engine from
      # splitting `<p class="foo">` into angle brackets, attribute names, and values.
      #
      # Tokenization regex: /<[^>]+>|[^\s<>]+/
      #   - /<[^>]+>/    matches any HTML tag: <p>, </p>, <div class="x">, <br/>
      #   - /[^\s<>]+/   matches words in text content between tags
      #
      # Example: "<p>Hello world</p>" → ["<p>", "Hello", "world", "</p>"]
      #
      # The :line key in change hashes stores the 1-indexed token position
      # (not a line number) for compatibility with Diff::Result serialization.
      class Html < Renderers::Base
        TAG_OR_WORD = /<[^>]+>|[^\s<>]+/.freeze

        # @param old_content [String]
        # @param new_content [String]
        # @return [Array<Hash>] change hashes with :type, :line (token index), and content keys
        def compute(old_content, new_content)
          old_tokens = tokenize(old_content)
          new_tokens = tokenize(new_content)
          changes    = []

          ::Diff::LCS.sdiff(old_tokens, new_tokens).each do |hunk|
            case hunk.action
            when "+"
              changes << { type: :addition, line: hunk.new_position + 1, content: hunk.new_element.to_s }
            when "-"
              changes << { type: :deletion, line: hunk.old_position + 1, content: hunk.old_element.to_s }
            when "!"
              changes << {
                type:        :modification,
                line:        hunk.old_position + 1,
                old_content: hunk.old_element.to_s,
                new_content: hunk.new_element.to_s
              }
            end
          end

          changes
        end

        private

        # Splits HTML into tokens:
        # - Each HTML tag (including attributes) is one token
        # - Each word in text content is one token
        # Whitespace between tokens is discarded.
        def tokenize(content)
          content.scan(TAG_OR_WORD)
        end
      end
    end
  end
end
