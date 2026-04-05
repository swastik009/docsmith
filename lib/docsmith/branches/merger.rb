# frozen_string_literal: true

require "diff/lcs"

module Docsmith
  module Branches
    # Three-way merge engine for document branches using line-level diff-lcs.
    #
    # Fast-forward: when main_head == source_version, branch content wins outright.
    # Three-way:    detect changes from source→main and source→branch.
    #               Auto-merge non-overlapping changes.
    #               Return conflicts for lines changed differently on both sides.
    class Merger
      # Internal struct — distinct from the public MergeResult (which has a persisted version).
      # merged_content is a String on success, nil on conflict.
      InternalResult = Struct.new(:merged_content, :conflicts, keyword_init: true) do
        def success?
          conflicts.empty?
        end
      end

      class << self
        # @param source_version [Docsmith::DocumentVersion] common ancestor (fork point)
        # @param branch_head    [Docsmith::DocumentVersion] latest version on the branch
        # @param main_head      [Docsmith::DocumentVersion] latest version on main
        # @return [InternalResult]
        def merge(source_version:, branch_head:, main_head:)
          # Fast-forward: main hasn't changed since the branch was created
          if main_head.id == source_version.id
            return InternalResult.new(merged_content: branch_head.content.to_s, conflicts: [])
          end

          three_way_merge(
            base:   source_version.content.to_s,
            ours:   main_head.content.to_s,
            theirs: branch_head.content.to_s
          )
        end

        private

        # Line-level three-way merge.
        # Applies non-conflicting changes from both sides onto the base.
        # Returns a conflict for each line changed differently by both sides.
        def three_way_merge(base:, ours:, theirs:)
          base_lines   = base.split("\n", -1)
          ours_lines   = ours.split("\n", -1)
          theirs_lines = theirs.split("\n", -1)

          ours_changes   = line_changes(base_lines, ours_lines)
          theirs_changes = line_changes(base_lines, theirs_lines)

          conflicts = detect_conflicts(base_lines, ours_changes, theirs_changes)
          return InternalResult.new(merged_content: nil, conflicts: conflicts) if conflicts.any?

          merged = apply_changes(base_lines, ours_lines, theirs_lines, ours_changes, theirs_changes)
          InternalResult.new(merged_content: merged.join("\n"), conflicts: [])
        end

        # Returns hash of { line_index => new_content } for lines changed vs base.
        # Deletions stored as nil.
        def line_changes(base_lines, new_lines)
          changes = {}
          ::Diff::LCS.sdiff(base_lines, new_lines).each do |hunk|
            case hunk.action
            when "!" then changes[hunk.old_position] = hunk.new_element
            when "-" then changes[hunk.old_position] = nil
            end
          end
          changes
        end

        # Detects lines changed differently by both sides.
        def detect_conflicts(base_lines, ours_changes, theirs_changes)
          conflicts = []
          (ours_changes.keys & theirs_changes.keys).each do |idx|
            next if ours_changes[idx] == theirs_changes[idx]  # identical change — no conflict

            conflicts << {
              line:           idx + 1,
              base_content:   base_lines[idx],
              main_content:   ours_changes[idx],
              branch_content: theirs_changes[idx]
            }
          end
          conflicts
        end

        # Applies all non-conflicting changes from both sides and appends tail additions.
        def apply_changes(base_lines, ours_lines, theirs_lines, ours_changes, theirs_changes)
          merged = base_lines.dup

          # Merge all changes — theirs overwrites ours for same line (no conflict possible here)
          all_changes = ours_changes.merge(theirs_changes)
          all_changes.each { |idx, new_line| merged[idx] = new_line }

          # Append lines added at the end by either side
          if theirs_lines.length > base_lines.length && ours_lines.length == base_lines.length
            merged += theirs_lines[base_lines.length..]
          elsif ours_lines.length > base_lines.length && theirs_lines.length == base_lines.length
            merged += ours_lines[base_lines.length..]
          end

          merged
        end
      end
    end
  end
end
