# frozen_string_literal: true

module Docsmith
  module Events
    # Immutable payload for all Docsmith events.
    # Fields on every event: record, document, version, author.
    # Extra fields by event:
    #   version_restored → from_version
    #   version_tagged   → tag_name
    #   comment_added/orphaned → comment  (Phase 3)
    #   branch_created/merged  → branch   (Phase 4)
    Event = Struct.new(
      :record, :document, :version, :author,
      :from_version, :tag_name,
      :comment, :branch, :conflicts, :merge_result,
      keyword_init: true
    )
  end
end
