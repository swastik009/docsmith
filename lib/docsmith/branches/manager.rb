# frozen_string_literal: true

module Docsmith
  module Branches
    # Service object for creating and merging document branches.
    class Manager
      class << self
        # Creates a new Branch forked from a specific version of the document.
        #
        # @param document [Docsmith::Document]
        # @param name [String]
        # @param from_version [Integer] version_number to fork from
        # @param author [Object]
        # @return [Docsmith::Branches::Branch]
        # @raise [ActiveRecord::RecordNotFound] if from_version does not exist
        def create!(document, name:, from_version:, author:)
          source = Docsmith::DocumentVersion.find_by!(document: document, version_number: from_version)

          branch = Branch.create!(
            document:       document,
            name:           name,
            source_version: source,
            author:         author,
            status:         "active"
          )

          Events::Notifier.instrument(:branch_created,
            record:   document.subject || document,
            document: document,
            version:  source,
            author:   author,
            branch:   branch
          )

          branch
        end

        # Merges a branch into the main document history.
        # Attempts fast-forward first, then three-way merge.
        # On success: creates new main version and marks branch merged.
        # On conflict: fires merge_conflict event; no version created.
        #
        # @param document [Docsmith::Document]
        # @param branch [Docsmith::Branches::Branch]
        # @param author [Object]
        # @return [Docsmith::MergeResult]
        def merge!(document, branch:, author:)
          branch_head = branch.head_version || branch.source_version
          source      = branch.source_version
          main_head   = document.document_versions.where(branch_id: nil).reorder(version_number: :desc).first!

          internal = Merger.merge(source_version: source, branch_head: branch_head, main_head: main_head)

          unless internal.success?
            result = MergeResult.new(merged_version: nil, conflicts: internal.conflicts)
            Events::Notifier.instrument(:merge_conflict,
              record:       document.subject || document,
              document:     document,
              version:      main_head,
              author:       author,
              branch:       branch,
              merge_result: result
            )
            return result
          end

          document.update_columns(content: internal.merged_content)

          # Create new main version explicitly
          next_num = document.versions_count + 1
          new_version = Docsmith::DocumentVersion.create!(
            document:       document,
            version_number: next_num,
            content:        internal.merged_content,
            content_type:   document.content_type,
            author:         author,
            change_summary: "Merge branch '#{branch.name}'",
            branch_id:      nil,
            metadata:       {}
          )

          document.update_columns(
            versions_count:    next_num,
            last_versioned_at: Time.current
          )

          branch.update_columns(status: "merged", merged_at: Time.current)

          result = MergeResult.new(merged_version: new_version, conflicts: [])
          Events::Notifier.instrument(:branch_merged,
            record:       document.subject || document,
            document:     document,
            version:      new_version,
            author:       author,
            branch:       branch,
            merge_result: result
          )
          result
        end
      end
    end
  end
end
