# frozen_string_literal: true

module Docsmith
  # The result object returned by merge_branch!.
  # On success: merged_version holds the newly created DocumentVersion.
  # On conflict: conflicts holds an array of conflict description hashes
  #   (each with :line, :base_content, :main_content, :branch_content).
  class MergeResult
    # @return [Docsmith::DocumentVersion, nil]
    attr_reader :merged_version
    # @return [Array<Hash>]
    attr_reader :conflicts

    # @param merged_version [Docsmith::DocumentVersion, nil]
    # @param conflicts [Array<Hash>]
    def initialize(merged_version:, conflicts:)
      @merged_version = merged_version
      @conflicts      = conflicts
    end

    # @return [Boolean] true when merge succeeded with no conflicts
    def success?
      conflicts.empty?
    end
  end
end
