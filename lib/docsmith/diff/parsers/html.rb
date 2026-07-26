# frozen_string_literal: true

require "diff/lcs"

module Docsmith
  module Diff
    module Parsers
      # HTML-aware diff parser for HTML documents.
      #
      # Tokenizes so each tag (with its attributes) is one atomic unit and text
      # words are separate units. This keeps the diff engine from splitting
      # `<p class="foo">` into angle brackets, attribute names, and values.
      #
      #   "<p>Hello world</p>" → ["<p>", "Hello", "world", "</p>"]
      #
      # Grouping, offsets, and rendering all come from Renderers::Base — this
      # class only decides where token boundaries fall.
      class Html < Renderers::Base
        # /<[^>]+>/  any tag: <p>, </p>, <div class="x">, <br/>
        # /[^\s<>]+/ words in text content between tags
        TAG_OR_WORD = /<[^>]+>|[^\s<>]+/

        # @param content [String]
        # @return [Array<Array(String, Integer)>] [token, start_offset] pairs
        def tokenize(content)
          scan_with_offsets(content, TAG_OR_WORD)
        end
      end
    end
  end
end
