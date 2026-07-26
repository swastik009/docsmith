# frozen_string_literal: true

require "diff/lcs"

module Docsmith
  module Diff
    module Parsers
      # Word-level diff parser for Markdown documents.
      #
      # Tokenizes into words and newline runs rather than lines, so prose edits
      # are detected at word granularity instead of "the whole line changed".
      #
      #   "Hello world\n\nFoo" → ["Hello", "world", "\n\n", "Foo"]
      #
      # Grouping, offsets, and rendering all come from Renderers::Base — this
      # class only decides where token boundaries fall. Spaces and tabs between
      # tokens are not themselves tokens, but they are still present in an edit's
      # `text`, which is sliced from the source between the edit's offsets.
      class Markdown < Renderers::Base
        # \S+ matches any non-whitespace run (words, punctuation, markdown markers).
        # \n+ matches consecutive newlines as one token, so a paragraph break
        # (\n\n) and a line break (\n) are each a single diffable unit.
        WORD_OR_NEWLINES = /\S+|\n+/

        # @param content [String]
        # @return [Array<Array(String, Integer)>] [token, start_offset] pairs
        def tokenize(content)
          scan_with_offsets(content, WORD_OR_NEWLINES)
        end
      end
    end
  end
end
