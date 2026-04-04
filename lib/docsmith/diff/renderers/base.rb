# frozen_string_literal: true

require "diff/lcs"
require "cgi"

module Docsmith
  module Diff
    module Renderers
      # Line-level diff renderer using diff-lcs.
      # Handles all content types (markdown, html, json) for Phase 2.
      # Register content-type-specific renderers via Renderers::Registry when needed.
      class Base
        # Computes line-level changes between two content strings.
        #
        # @param old_content [String]
        # @param new_content [String]
        # @return [Array<Hash>] change hashes with :type, :line, and content fields
        def compute(old_content, new_content)
          old_lines = old_content.split("\n", -1)
          new_lines = new_content.split("\n", -1)
          changes   = []

          ::Diff::LCS.sdiff(old_lines, new_lines).each do |hunk|
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

        # Renders a change array as an HTML diff representation.
        #
        # @param changes [Array<Hash>]
        # @return [String] HTML string
        def render_html(changes)
          lines = changes.map do |change|
            case change[:type]
            when :addition
              %(<ins class="docsmith-addition">#{CGI.escapeHTML(change[:content])}</ins>)
            when :deletion
              %(<del class="docsmith-deletion">#{CGI.escapeHTML(change[:content])}</del>)
            when :modification
              %(<del class="docsmith-deletion">#{CGI.escapeHTML(change[:old_content])}</del><ins class="docsmith-addition">#{CGI.escapeHTML(change[:new_content])}</ins>)
            end
          end
          %(<div class="docsmith-diff">#{lines.join("\n")}</div>)
        end
      end
    end
  end
end
