# frozen_string_literal: true

require "diff/lcs"

module Docsmith
  module Diff
    module Parsers
      # Word-level diff parser for Markdown documents.
      #
      # Instead of comparing line-by-line (as Renderers::Base does), this parser
      # tokenizes content into individual words and newline groups, then diffs
      # those tokens. This gives precise word-level change detection for prose,
      # which is far more useful than "the whole line changed."
      #
      # Tokenization: content.scan(/\S+|\n+/)
      #   "Hello world\n\nFoo" → ["Hello", "world", "\n\n", "Foo"]
      #
      # The :line key in change hashes stores the 1-indexed token position
      # (not a line number) for compatibility with Diff::Result serialization.
      class Markdown < Renderers::Base
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

        # Splits markdown into word tokens.
        # \S+ matches any non-whitespace run (words, punctuation, markdown markers).
        # \n+ matches one or more consecutive newlines as a single token so that
        # paragraph breaks (\n\n) and line breaks (\n) are each one diffable unit.
        def tokenize(content)
          content.scan(/\S+|\n+/)
        end
      end
    end
  end
end
