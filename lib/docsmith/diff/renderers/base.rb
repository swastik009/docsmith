# frozen_string_literal: true

require "diff/lcs"
require "cgi"

module Docsmith
  module Diff
    module Renderers
      # Line-level diff renderer, and the base for the format-aware parsers.
      #
      # Subclasses override #tokenize only. All grouping, offset arithmetic, and
      # HTML rendering lives here, so every content type produces the same edit
      # structure and only the token boundaries differ.
      #
      # An edit is a contiguous run of changes collapsed into one entry:
      #
      #   { type: :replace,
      #     old:  { start: 0, end: 11, line: 1, column: 1, text: "my document" },
      #     new:  { start: 0, end: 30, line: 1, column: 1, text: "<h1>..." } }
      #
      # Both sides are always present. A pure insertion carries a zero-width old
      # span at the insertion point; a pure deletion a zero-width new span. Every
      # edit therefore has identical keys, and offsets on the two sides never
      # share a coordinate space.
      #
      # `text` is sliced straight out of the source between the run's offsets, so
      # whitespace the tokenizer discarded is preserved verbatim and both
      # documents round-trip exactly.
      class Base
        # Actions that consume a token from the old side / the new side.
        OLD_SIDE = %w[- !].freeze
        NEW_SIDE = %w[+ !].freeze

        # Splits content into [text, start_offset] pairs. Lines here, excluding
        # the newline itself. Override in subclasses for other content types.
        #
        # The newline is deliberately not part of the token: including it made
        # appending a line report the *previous* line as changed, because that
        # line gained a trailing newline. Empty lines are preserved as empty
        # tokens so that blank-line changes are still detected.
        #
        # @param content [String]
        # @return [Array<Array(String, Integer)>]
        def tokenize(content)
          offset = 0
          content.to_s.split("\n", -1).map do |line|
            token = [line, offset]
            offset += line.length + 1
            token
          end
        end

        # Computes grouped edits between two content strings.
        #
        # @param old_content [String]
        # @param new_content [String]
        # @return [Array<Hash>] edit hashes with :type, :old and :new
        def compute(old_content, new_content)
          old_content = old_content.to_s
          new_content = new_content.to_s
          old_tokens  = tokenize(old_content)
          new_tokens  = tokenize(new_content)

          edits = []
          run   = []

          ::Diff::LCS.sdiff(old_tokens.map(&:first), new_tokens.map(&:first)).each do |hunk|
            if hunk.action == "="
              edits << build_edit(run, old_tokens, new_tokens, old_content, new_content) unless run.empty?
              run = []
            else
              run << hunk
            end
          end
          edits << build_edit(run, old_tokens, new_tokens, old_content, new_content) unless run.empty?

          edits
        end

        # Renders grouped edits as an HTML diff representation.
        #
        # @param edits [Array<Hash>]
        # @return [String] HTML string
        def render_html(edits)
          lines = edits.map do |edit|
            case edit[:type]
            when :insert  then insertion(edit[:new][:text])
            when :delete  then deletion(edit[:old][:text])
            when :replace then deletion(edit[:old][:text]) + insertion(edit[:new][:text])
            end
          end
          %(<div class="docsmith-diff">#{lines.join("\n")}</div>)
        end

        private

        def insertion(text)
          %(<ins class="docsmith-addition">#{CGI.escapeHTML(text.to_s)}</ins>)
        end

        def deletion(text)
          %(<del class="docsmith-deletion">#{CGI.escapeHTML(text.to_s)}</del>)
        end

        # Collects every match with its start offset. scan sets Regexp.last_match
        # per iteration when a block is given.
        def scan_with_offsets(content, pattern)
          matches = []
          content.to_s.scan(pattern) { matches << [::Regexp.last_match(0), ::Regexp.last_match.begin(0)] }
          matches
        end

        def build_edit(run, old_tokens, new_tokens, old_content, new_content)
          old_indexes = run.select { |h| OLD_SIDE.include?(h.action) }.map(&:old_position)
          new_indexes = run.select { |h| NEW_SIDE.include?(h.action) }.map(&:new_position)

          {
            type: edit_type(old_indexes, new_indexes),
            old:  span(old_content, old_tokens, old_indexes, run.first.old_position),
            new:  span(new_content, new_tokens, new_indexes, run.first.new_position)
          }
        end

        def edit_type(old_indexes, new_indexes)
          return :insert if old_indexes.empty?
          return :delete if new_indexes.empty?

          :replace
        end

        # @param indexes [Array<Integer>] token indexes this run touches on this side
        # @param fallback_index [Integer] token index to anchor a zero-width span at
        def span(content, tokens, indexes, fallback_index)
          if indexes.empty?
            start  = token_start(tokens, fallback_index, content)
            finish = start
          else
            last_text, last_start = tokens[indexes.last]
            start  = tokens[indexes.first][1]
            finish = last_start + last_text.length
          end

          line, column = line_and_column(content, start)
          { start: start, end: finish, line: line, column: column, text: content[start...finish].to_s }
        end

        # Character offset a token begins at; end of content when past the last token.
        def token_start(tokens, index, content)
          index < tokens.length ? tokens[index][1] : content.length
        end

        # 1-indexed line and column for a character offset.
        def line_and_column(content, offset)
          prefix       = content[0, offset].to_s
          last_newline = prefix.rindex("\n")

          [prefix.count("\n") + 1, last_newline.nil? ? offset + 1 : offset - last_newline]
        end
      end
    end
  end
end
