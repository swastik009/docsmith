# Docsmith: Format-Aware Parsers, Remove Branches, Docs

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add word-level Markdown and HTML-aware diff parsers, strip all branching/merging code, and write complete documentation.

**Architecture:** The diff `Engine` gains a `PARSERS` map (content-type → parser class) that overrides the generic line-level `Renderers::Base` for markdown and html documents. Parsers inherit `Renderers::Base`, overriding only `compute`. Branch code (3 lib files, 1 result file, 9 spec files, schema table, generator template) is deleted wholesale. The `Renderers::Registry` is left untouched—it still exists for custom rendering overrides.

**Tech Stack:** Ruby, diff-lcs, RSpec, ActiveRecord (SQLite in tests)

---

## File Map

```
# Created
lib/docsmith/diff/parsers/markdown.rb         ← word-level tokenizer, inherits Renderers::Base
lib/docsmith/diff/parsers/html.rb             ← HTML-tag-aware tokenizer, inherits Renderers::Base
spec/docsmith/diff/parsers/markdown_spec.rb   ← unit tests for Markdown parser
spec/docsmith/diff/parsers/html_spec.rb       ← unit tests for HTML parser
USAGE.md                                       ← verbose usage guide

# Deleted
lib/docsmith/branches/branch.rb
lib/docsmith/branches/manager.rb
lib/docsmith/branches/merger.rb
lib/docsmith/merge_result.rb
spec/docsmith/branches/branch_spec.rb
spec/docsmith/branches/manager_spec.rb
spec/docsmith/branches/merger_spec.rb
spec/docsmith/merge_result_spec.rb
spec/docsmith/phase4_integration_spec.rb

# Modified
lib/docsmith.rb                               ← remove branch/merge_result requires, add parser requires (before engine require)
lib/docsmith/diff/engine.rb                   ← add PARSERS constant, use parser in between()
lib/docsmith/versionable.rb                   ← remove branch: param from save_version!, delete 4 branch methods
lib/docsmith/version_manager.rb               ← remove branch: param + branch_id + branch.update_columns from save!
lib/docsmith/document_version.rb              ← remove belongs_to :branch
spec/support/schema.rb                        ← remove branch_id column + docsmith_branches table
lib/generators/.../create_docsmith_tables.rb.erb ← remove docsmith_branches + branch_id
lib/generators/.../docsmith_initializer.rb.erb   ← clean up stale comments
spec/docsmith/versionable_spec.rb             ← remove branch describe blocks + fix addition count
spec/docsmith/diff/engine_spec.rb             ← fix addition count (1 → 3 for word-level)
spec/docsmith/phase2_integration_spec.rb      ← fix addition count (1 → 3 for word-level)
docsmith.gemspec                              ← update description
README.md                                     ← rewrite with gem overview + link to USAGE.md
```

---

## Task 1: Delete Branch Files

**Files:**
- Delete: `lib/docsmith/branches/branch.rb`
- Delete: `lib/docsmith/branches/manager.rb`
- Delete: `lib/docsmith/branches/merger.rb`
- Delete: `lib/docsmith/merge_result.rb`
- Delete: `spec/docsmith/branches/branch_spec.rb`
- Delete: `spec/docsmith/branches/manager_spec.rb`
- Delete: `spec/docsmith/branches/merger_spec.rb`
- Delete: `spec/docsmith/merge_result_spec.rb`
- Delete: `spec/docsmith/phase4_integration_spec.rb`

- [ ] **Step 1: Delete branch lib files and merge_result**

```bash
rm lib/docsmith/branches/branch.rb
rm lib/docsmith/branches/manager.rb
rm lib/docsmith/branches/merger.rb
rm lib/docsmith/merge_result.rb
rmdir lib/docsmith/branches
```

- [ ] **Step 2: Delete branch spec files and phase4 spec**

```bash
rm spec/docsmith/branches/branch_spec.rb
rm spec/docsmith/branches/manager_spec.rb
rm spec/docsmith/branches/merger_spec.rb
rm spec/docsmith/merge_result_spec.rb
rm spec/docsmith/phase4_integration_spec.rb
rmdir spec/docsmith/branches
```

---

## Task 2: Scrub Branch References from Core Files

**Files:**
- Modify: `lib/docsmith.rb`
- Modify: `lib/docsmith/versionable.rb`
- Modify: `lib/docsmith/version_manager.rb`
- Modify: `lib/docsmith/document_version.rb`

- [ ] **Step 1: Remove branch and merge_result requires from `lib/docsmith.rb`**

Replace the entire file content with:

```ruby
# frozen_string_literal: true

require "active_record"
require "active_support"
require "active_support/core_ext/numeric/time"
require "active_support/notifications"

require_relative "docsmith/version"
require_relative "docsmith/errors"
require_relative "docsmith/configuration"
require_relative "docsmith/events/event"
require_relative "docsmith/events/hook_registry"
require_relative "docsmith/events/notifier"
require_relative "docsmith/document"
require_relative "docsmith/document_version"
require_relative "docsmith/version_tag"
require_relative "docsmith/auto_save"
require_relative "docsmith/version_manager"
require_relative "docsmith/versionable"
require_relative "docsmith/diff"
require_relative "docsmith/diff/renderers"
require_relative "docsmith/diff/renderers/base"
require_relative "docsmith/diff/renderers/registry"
require_relative "docsmith/diff/result"
require_relative "docsmith/diff/parsers/markdown"
require_relative "docsmith/diff/parsers/html"
require_relative "docsmith/diff/engine"
require_relative "docsmith/rendering/html_renderer"
require_relative "docsmith/rendering/json_renderer"
require_relative "docsmith/comments/comment"
require_relative "docsmith/comments/anchor"
require_relative "docsmith/comments/manager"
require_relative "docsmith/comments/migrator"

module Docsmith
  class << self
    # @yield [Docsmith::Configuration]
    def configure
      yield configuration
    end

    # @return [Docsmith::Configuration]
    def configuration
      @configuration ||= Configuration.new
    end

    # Reset to gem defaults. Call in specs via config.before(:each).
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
```

- [ ] **Step 2: Remove branch param from `save_version!` and delete 4 branch methods in `lib/docsmith/versionable.rb`**

Replace the file content with (full new content — removes `branch:` param from `save_version!` and removes `create_branch!`, `branches`, `active_branches`, `merge_branch!`):

```ruby
# frozen_string_literal: true

module Docsmith
  # ActiveRecord mixin that adds full versioning to any model.
  #
  # Usage:
  #   class Article < ApplicationRecord
  #     include Docsmith::Versionable
  #     docsmith_config { content_field :body; content_type :markdown }
  #   end
  module Versionable
    def self.included(base)
      base.extend(ClassMethods)
      base.after_save(:_docsmith_auto_save_callback)
    end

    module ClassMethods
      # Configure per-class Docsmith options. All keys optional.
      # Unset keys fall through to global config then gem defaults.
      # @yield block evaluated on a Docsmith::ClassConfig instance
      # @return [Docsmith::ClassConfig]
      def docsmith_config(&block)
        @_docsmith_class_config ||= Docsmith::ClassConfig.new
        @_docsmith_class_config.instance_eval(&block) if block_given?
        @_docsmith_class_config
      end

      # @return [Hash] fully resolved config (read-time resolution)
      def docsmith_resolved_config
        Docsmith::Configuration.resolve(
          @_docsmith_class_config&.settings || {},
          Docsmith.configuration
        )
      end
    end

    # Create a new DocumentVersion snapshot of this record's content.
    # Returns nil if content is identical to the latest version.
    # Raises Docsmith::InvalidContentField if content_field returns a non-String
    # and no content_extractor is configured.
    #
    # @param author [Object, nil]
    # @param summary [String, nil]
    # @return [Docsmith::DocumentVersion, nil]
    def save_version!(author:, summary: nil)
      _sync_docsmith_content!
      Docsmith::VersionManager.save!(
        _docsmith_document,
        author:  author,
        summary: summary,
        config:  self.class.docsmith_resolved_config
      )
    end

    # Debounced auto-save. Returns nil if debounce window has not elapsed
    # OR content is unchanged. Both non-save cases return nil.
    # auto_save: false in config causes this to always return nil.
    #
    # @param author [Object, nil]
    # @return [Docsmith::DocumentVersion, nil]
    def auto_save_version!(author: nil)
      config = self.class.docsmith_resolved_config
      return nil unless config[:auto_save]

      _sync_docsmith_content!
      Docsmith::AutoSave.call(_docsmith_document, author: author, config: config)
    end

    # @return [ActiveRecord::Relation<Docsmith::DocumentVersion>] ordered by version_number
    def versions
      _docsmith_document.document_versions
    end

    # @return [Docsmith::DocumentVersion, nil] latest version
    def current_version
      _docsmith_document.current_version
    end

    # @param number [Integer] 1-indexed version_number
    # @return [Docsmith::DocumentVersion, nil]
    def version(number)
      _docsmith_document.document_versions.find_by(version_number: number)
    end

    # Restore to a previous version. Creates a new version with the old content.
    # Syncs restored content back to the model's content_field via update_column
    # (bypasses after_save to prevent a duplicate auto-save).
    # Never mutates existing versions.
    #
    # @param number [Integer] version_number to restore from
    # @param author [Object, nil]
    # @return [Docsmith::DocumentVersion]
    # @raise [Docsmith::VersionNotFound]
    def restore_version!(number, author:)
      result = Docsmith::VersionManager.restore!(
        _docsmith_document,
        version: number,
        author:  author,
        config:  self.class.docsmith_resolved_config
      )
      field = self.class.docsmith_resolved_config[:content_field]
      update_column(field, _docsmith_document.reload.content)
      result
    end

    # Tag a specific version. Names are unique per document.
    # @param number [Integer] version_number to tag
    # @param name [String]
    # @param author [Object, nil]
    # @return [Docsmith::VersionTag]
    def tag_version!(number, name:, author:)
      Docsmith::VersionManager.tag!(
        _docsmith_document, version: number, name: name, author: author)
    end

    # @param tag_name [String]
    # @return [Docsmith::DocumentVersion, nil]
    def tagged_version(tag_name)
      tag = _docsmith_document.version_tags.find_by(name: tag_name)
      tag&.version
    end

    # @param number [Integer] version_number
    # @return [Array<String>] tag names on that version
    def version_tags(number)
      ver = version(number)
      return [] unless ver
      ver.version_tags.pluck(:name)
    end

    # Computes a diff from version N to the current (latest) version.
    #
    # @param version_number [Integer]
    # @return [Docsmith::Diff::Result]
    # @raise [ActiveRecord::RecordNotFound] if version_number does not exist
    def diff_from(version_number)
      doc    = _docsmith_document
      v_from = Docsmith::DocumentVersion.find_by!(document: doc, version_number: version_number)
      v_to   = Docsmith::DocumentVersion.where(document_id: doc.id).order(version_number: :desc).first!
      Docsmith::Diff.between(v_from, v_to)
    end

    # Computes a diff between two named versions.
    #
    # @param from_version [Integer]
    # @param to_version [Integer]
    # @return [Docsmith::Diff::Result]
    # @raise [ActiveRecord::RecordNotFound] if either version does not exist
    def diff_between(from_version, to_version)
      doc    = _docsmith_document
      v_from = Docsmith::DocumentVersion.find_by!(document: doc, version_number: from_version)
      v_to   = Docsmith::DocumentVersion.find_by!(document: doc, version_number: to_version)
      Docsmith::Diff.between(v_from, v_to)
    end

    # Adds a comment to a specific version of this document.
    #
    # @param version [Integer] version_number
    # @param body [String]
    # @param author [Object] polymorphic author
    # @param anchor [Hash, nil] { start_offset:, end_offset: } for inline range comments
    # @param parent [Comments::Comment, nil] parent comment for threading
    # @return [Docsmith::Comments::Comment]
    def add_comment!(version:, body:, author:, anchor: nil, parent: nil)
      Comments::Manager.add!(
        _docsmith_document,
        version_number: version,
        body:           body,
        author:         author,
        anchor:         anchor,
        parent:         parent
      )
    end

    # Returns all comments across all versions of this document.
    #
    # @return [ActiveRecord::Relation<Docsmith::Comments::Comment>]
    def comments
      doc = _docsmith_document
      Comments::Comment.joins(:version)
                       .where(docsmith_versions: { document_id: doc.id })
    end

    # Returns comments on a specific version, optionally filtered by anchor type.
    #
    # @param version [Integer] version_number
    # @param type [Symbol, nil] :document or :range to filter; nil = all
    # @return [ActiveRecord::Relation<Docsmith::Comments::Comment>]
    def comments_on(version:, type: nil)
      doc = _docsmith_document
      dv  = Docsmith::DocumentVersion.find_by!(document: doc, version_number: version)
      rel = Comments::Comment.where(version: dv)
      rel = rel.where(anchor_type: type.to_s) if type
      rel
    end

    # Returns all unresolved comments across all versions.
    #
    # @return [ActiveRecord::Relation<Docsmith::Comments::Comment>]
    def unresolved_comments
      comments.merge(Comments::Comment.unresolved)
    end

    # Migrates top-level comments from one version to another.
    #
    # @param from [Integer] source version_number
    # @param to [Integer] target version_number
    # @return [void]
    def migrate_comments!(from:, to:)
      Comments::Migrator.migrate!(_docsmith_document, from: from, to: to)
    end

    private

    # Finds or creates the shadow Docsmith::Document for this record.
    # Cached in @_docsmith_document after first lookup.
    def _docsmith_document
      config = self.class.docsmith_resolved_config
      @_docsmith_document ||= Docsmith::Document.find_or_create_by!(subject: self) do |doc|
        doc.content_type = config[:content_type].to_s
        doc.title        = respond_to?(:title) ? title.to_s : self.class.name
      end
    end

    # Reads content from the model via content_extractor or content_field,
    # validates it is a String, then syncs to the shadow document's content column.
    def _sync_docsmith_content!
      config = self.class.docsmith_resolved_config

      raw = if config[:content_extractor]
              config[:content_extractor].call(self)
            else
              public_send(config[:content_field])
            end

      unless raw.nil? || raw.is_a?(String)
        source = config[:content_extractor] ? "content_extractor" : "content_field :#{config[:content_field]}"
        raise Docsmith::InvalidContentField,
          "#{source} must return a String, got #{raw.class}. " \
          "Use content_extractor: ->(record) { ... } for non-string fields."
      end

      _docsmith_document.update_column(:content, raw.to_s)
    end

    def _docsmith_auto_save_callback
      auto_save_version!
    rescue Docsmith::InvalidContentField
      nil
    end
  end
end
```

- [ ] **Step 3: Remove branch param from `VersionManager.save!` in `lib/docsmith/version_manager.rb`**

Replace the file content with:

```ruby
# frozen_string_literal: true

module Docsmith
  # Service object for all version lifecycle operations.
  # The Versionable mixin delegates here after resolving the shadow document.
  # Always receives a Docsmith::Document instance.
  module VersionManager
    # Create a new DocumentVersion snapshot.
    # Returns nil if content is identical to the latest version (string == check).
    #
    # @param document [Docsmith::Document]
    # @param author [Object, nil]
    # @param summary [String, nil]
    # @param config [Hash] resolved config
    # @return [Docsmith::DocumentVersion, nil]
    def self.save!(document, author:, summary: nil, config: nil)
      config  ||= Configuration.resolve({}, Docsmith.configuration)
      current   = document.content.to_s
      latest    = document.document_versions.last

      return nil if latest && latest.content == current

      next_num = document.versions_count + 1

      version = DocumentVersion.create!(
        document:       document,
        version_number: next_num,
        content:        current,
        content_type:   document.content_type,
        author:         author,
        change_summary: summary,
        metadata:       {}
      )

      document.update_columns(
        versions_count:    next_num,
        last_versioned_at: Time.current
      )
      document.versions_count = next_num

      prune_if_needed!(document, version, config) if config[:max_versions]

      record = document.subject || document
      Events::Notifier.instrument(:version_created,
        record: record, document: document, version: version, author: author)

      version
    end

    # Restore a previous version by creating a new version with its content.
    # Fires :version_restored (not :version_created). Never mutates existing versions.
    #
    # @param document [Docsmith::Document]
    # @param version [Integer] version_number to restore from
    # @param author [Object, nil]
    # @param config [Hash] resolved config
    # @return [Docsmith::DocumentVersion] the new version
    # @raise [Docsmith::VersionNotFound]
    def self.restore!(document, version:, author:, config: nil)
      config      ||= Configuration.resolve({}, Docsmith.configuration)
      from_version  = document.document_versions.find_by(version_number: version)
      raise VersionNotFound, "Version #{version} not found on this document" unless from_version

      next_num = document.versions_count + 1

      new_version = DocumentVersion.create!(
        document:       document,
        version_number: next_num,
        content:        from_version.content,
        content_type:   document.content_type,
        author:         author,
        change_summary: "Restored from v#{version}",
        metadata:       {}
      )

      document.update_columns(
        content:           from_version.content,
        versions_count:    next_num,
        last_versioned_at: Time.current
      )

      record = document.subject || document
      Events::Notifier.instrument(:version_restored,
        record: record, document: document, version: new_version,
        author: author, from_version: from_version)

      new_version
    end

    # Tag a specific version with a name unique to this document.
    #
    # @param document [Docsmith::Document]
    # @param version [Integer] version_number to tag
    # @param name [String] unique per document
    # @param author [Object, nil]
    # @return [Docsmith::VersionTag]
    # @raise [Docsmith::VersionNotFound]
    # @raise [Docsmith::TagAlreadyExists]
    def self.tag!(document, version:, name:, author:)
      version_record = document.document_versions.find_by(version_number: version)
      raise VersionNotFound, "Version #{version} not found on this document" unless version_record

      if VersionTag.exists?(document_id: document.id, name: name)
        raise TagAlreadyExists, "Tag '#{name}' already exists on this document"
      end

      tag = VersionTag.create!(
        document: document,
        version:  version_record,
        name:     name,
        author:   author
      )

      record = document.subject || document
      Events::Notifier.instrument(:version_tagged,
        record: record, document: document, version: version_record,
        author: author, tag_name: name)

      tag
    end

    def self.prune_if_needed!(document, new_version, config)
      max = config[:max_versions]
      return unless max && document.versions_count > max

      tagged_ids      = VersionTag.where(document_id: document.id).select(:version_id)
      oldest_untagged = document.document_versions
                                .where.not(id: tagged_ids)
                                .where.not(id: new_version.id)
                                .first

      unless oldest_untagged
        raise MaxVersionsExceeded,
          "All #{document.versions_count} versions are tagged. Cannot prune to stay within " \
          "max_versions: #{max}. Remove a tag or increase max_versions."
      end

      oldest_untagged.destroy!
      document.update_column(:versions_count, document.versions_count - 1)
    end
    private_class_method :prune_if_needed!
  end
end
```

- [ ] **Step 4: Remove `belongs_to :branch` from `lib/docsmith/document_version.rb`**

Replace lines 14–15 (the branch association and its blank line):

```ruby
# REMOVE these two lines:
    belongs_to :branch, class_name: "Docsmith::Branches::Branch", optional: true
```

The updated associations block becomes:

```ruby
    belongs_to :document,
               class_name:  "Docsmith::Document",
               foreign_key: :document_id
    belongs_to :author, polymorphic: true, optional: true
    has_many   :version_tags,
               class_name:  "Docsmith::VersionTag",
               foreign_key: :version_id,
               dependent:   :destroy
    has_many :comments,
             class_name:  "Docsmith::Comments::Comment",
             foreign_key: :version_id,
             dependent:   :destroy
```

Full file after edit:

```ruby
# frozen_string_literal: true

module Docsmith
  # Immutable content snapshot. Table is docsmith_versions.
  class DocumentVersion < ActiveRecord::Base
    self.table_name = "docsmith_versions"

    belongs_to :document,
               class_name:  "Docsmith::Document",
               foreign_key: :document_id
    belongs_to :author, polymorphic: true, optional: true
    has_many   :version_tags,
               class_name:  "Docsmith::VersionTag",
               foreign_key: :version_id,
               dependent:   :destroy
    has_many :comments,
             class_name:  "Docsmith::Comments::Comment",
             foreign_key: :version_id,
             dependent:   :destroy

    validates :version_number, presence: true,
              uniqueness: { scope: :document_id }
    validates :content,      presence: true
    validates :content_type, presence: true,
              inclusion: { in: %w[html markdown json] }

    # @return [Docsmith::DocumentVersion, nil]
    def previous_version
      document.document_versions
              .where("version_number < ?", version_number)
              .last
    end

    # Renders this version's content in the given output format.
    #
    # @param format [Symbol] :html or :json
    # @param options [Hash] passed through to the renderer
    # @return [String]
    # @raise [ArgumentError] for unknown formats
    def render(format, **options)
      case format.to_sym
      when :html then Rendering::HtmlRenderer.new.render(self, **options)
      when :json then Rendering::JsonRenderer.new.render(self, **options)
      else raise ArgumentError, "Unknown render format: #{format}. Supported: :html, :json"
      end
    end
  end
end
```

---

## Task 3: Remove Branch Schema and Generator Template

**Files:**
- Modify: `spec/support/schema.rb`
- Modify: `lib/generators/docsmith/install/templates/create_docsmith_tables.rb.erb`
- Modify: `lib/generators/docsmith/install/templates/docsmith_initializer.rb.erb`

- [ ] **Step 1: Remove `branch_id` column and `docsmith_branches` table from `spec/support/schema.rb`**

Replace the file with:

```ruby
# frozen_string_literal: true

# In-memory SQLite schema for tests.
# Mirrors db/migrate/create_docsmith_tables.rb with two intentional differences:
#   1. :jsonb columns use :text here (SQLite has no jsonb type)
#   2. Foreign key constraints are omitted (SQLite does not enforce them)
# Production migration uses :jsonb and add_foreign_key for PostgreSQL.

ActiveRecord::Schema.define do
  create_table :docsmith_documents, force: true do |t|
    t.string   :title
    t.text     :content
    t.string   :content_type,       null: false, default: "markdown"
    t.integer  :versions_count,     null: false, default: 0
    t.datetime :last_versioned_at
    t.string   :subject_type
    t.bigint   :subject_id
    t.text     :metadata,           default: "{}"
    t.timestamps
  end
  add_index :docsmith_documents, %i[subject_type subject_id]

  create_table :docsmith_versions, force: true do |t|
    t.bigint   :document_id,      null: false
    t.integer  :version_number,   null: false
    t.text     :content,          null: false
    t.string   :content_type,     null: false
    t.string   :author_type
    t.bigint   :author_id
    t.string   :change_summary
    t.text     :metadata,         default: "{}"
    t.datetime :created_at,       null: false
  end
  add_index :docsmith_versions, %i[document_id version_number], unique: true
  add_index :docsmith_versions, %i[author_type author_id]

  create_table :docsmith_version_tags, force: true do |t|
    t.bigint   :document_id,   null: false
    t.bigint   :version_id,    null: false
    t.string   :name,          null: false
    t.string   :author_type
    t.bigint   :author_id
    t.datetime :created_at,    null: false
  end
  add_index :docsmith_version_tags, %i[document_id name], unique: true
  add_index :docsmith_version_tags, %i[version_id]

  create_table :articles, force: true do |t|
    t.string :title
    t.text   :body
    t.timestamps
  end

  create_table :posts, force: true do |t|
    t.text :body
    t.timestamps
  end

  create_table :users, force: true do |t|
    t.string :name
    t.timestamps
  end

  create_table :docsmith_comments, force: true do |t|
    t.bigint   :version_id,        null: false
    t.bigint   :parent_id
    t.string   :author_type
    t.bigint   :author_id
    t.text     :body,              null: false
    t.string   :anchor_type,       null: false, default: "document"
    t.text     :anchor_data,       null: false, default: "{}"
    t.boolean  :resolved,          null: false, default: false
    t.string   :resolved_by_type
    t.bigint   :resolved_by_id
    t.datetime :resolved_at
    t.datetime :created_at,        null: false
    t.datetime :updated_at,        null: false
  end
  add_index :docsmith_comments, :version_id
  add_index :docsmith_comments, :parent_id
  add_index :docsmith_comments, %i[author_type author_id]
end
```

- [ ] **Step 2: Remove `docsmith_branches` table and `branch_id` from the migration template**

Replace `lib/generators/docsmith/install/templates/create_docsmith_tables.rb.erb` with:

```erb
# frozen_string_literal: true

class CreateDocsmithTables < ActiveRecord::Migration[<%= ActiveRecord::Migration.current_version %>]
  def change
    create_table :docsmith_documents do |t|
      t.string   :title
      t.text     :content
      t.string   :content_type,       null: false, default: "markdown"
      t.integer  :versions_count,     null: false, default: 0
      t.datetime :last_versioned_at
      t.string   :subject_type
      t.bigint   :subject_id
      t.jsonb    :metadata,           null: false, default: {}
      t.timestamps
    end
    add_index :docsmith_documents, %i[subject_type subject_id]

    create_table :docsmith_versions do |t|
      t.references :document,       null: false, foreign_key: { to_table: :docsmith_documents }
      t.integer    :version_number, null: false
      t.text       :content,        null: false
      t.string     :content_type,   null: false
      t.string     :author_type
      t.bigint     :author_id
      t.string     :change_summary
      t.jsonb      :metadata,       null: false, default: {}
      t.datetime   :created_at,     null: false
    end
    add_index :docsmith_versions, %i[document_id version_number], unique: true
    add_index :docsmith_versions, %i[author_type author_id]

    create_table :docsmith_version_tags do |t|
      t.references :document,   null: false, foreign_key: { to_table: :docsmith_documents }
      t.bigint     :version_id, null: false
      t.string     :name,       null: false
      t.string     :author_type
      t.bigint     :author_id
      t.datetime   :created_at, null: false
    end
    add_index :docsmith_version_tags, %i[document_id name], unique: true
    add_index :docsmith_version_tags, [:version_id]
    add_foreign_key :docsmith_version_tags, :docsmith_versions, column: :version_id

    create_table :docsmith_comments do |t|
      t.bigint   :version_id,        null: false
      t.bigint   :parent_id
      t.string   :author_type
      t.bigint   :author_id
      t.text     :body,              null: false
      t.string   :anchor_type,       null: false, default: "document"
      t.jsonb    :anchor_data,       null: false, default: {}
      t.boolean  :resolved,          null: false, default: false
      t.string   :resolved_by_type
      t.bigint   :resolved_by_id
      t.datetime :resolved_at
      t.timestamps                   null: false
    end
    add_index :docsmith_comments, :version_id
    add_index :docsmith_comments, :parent_id
    add_index :docsmith_comments, [:author_type, :author_id]
    add_foreign_key :docsmith_comments, :docsmith_versions, column: :version_id
    add_foreign_key :docsmith_comments, :docsmith_comments, column: :parent_id
  end
end
```

- [ ] **Step 3: Clean up initializer template comments**

Replace `lib/generators/docsmith/install/templates/docsmith_initializer.rb.erb` with:

```erb
# frozen_string_literal: true

Docsmith.configure do |config|
  # Resolution order: per-class docsmith_config > this global config > gem defaults
  #
  # config.default_content_field    = :body          # gem default: :body
  # config.default_content_type     = :markdown      # gem default: :markdown (:html, :markdown, :json)
  # config.auto_save                = true           # gem default: true
  # config.default_debounce         = 30             # gem default: 30 (integer seconds)
  # config.max_versions             = nil            # gem default: nil (unlimited)
  # config.content_extractor        = nil            # example: ->(record) { record.body.to_html }
  # config.table_prefix             = "docsmith"     # gem default: "docsmith"
  # config.diff_context_lines       = 3
  #
  # Event hooks (fires synchronously before AS::Notifications):
  # config.on(:version_created)  { |event| Rails.logger.info "v#{event.version.version_number} saved" }
  # config.on(:version_restored) { |event| }
  # config.on(:version_tagged)   { |event| }
end
```

- [ ] **Step 4: Verify tests pass after branch removal**

Run: `bundle exec rspec --format progress`

Expected: all remaining specs pass (branch specs are deleted, so no failures from them).

If you see `undefined method 'branch'` errors anywhere, check that all reference removals were complete.

- [ ] **Step 5: Commit branch removal**

```bash
git add -A
git commit -m "feat: remove branching and merging — too heavyweight for a document versioning gem"
```

---

## Task 4: Implement Markdown Diff Parser

**Files:**
- Create: `lib/docsmith/diff/parsers/markdown.rb`
- Create: `spec/docsmith/diff/parsers/markdown_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/docsmith/diff/parsers/markdown_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Diff::Parsers::Markdown do
  subject(:parser) { described_class.new }

  describe "#compute" do
    it "detects a word addition between versions" do
      # "Hello world" → "Hello Ruby world"
      # Old tokens: ["Hello", "world"]
      # New tokens: ["Hello", "Ruby", "world"]
      # LCS: ["Hello", "world"] — "Ruby" is inserted
      changes = parser.compute("Hello world", "Hello Ruby world")
      expect(changes).to include(a_hash_including(type: :addition, content: "Ruby"))
    end

    it "detects a word deletion between versions" do
      # "Hello Ruby world" → "Hello world"
      changes = parser.compute("Hello Ruby world", "Hello world")
      expect(changes).to include(a_hash_including(type: :deletion, content: "Ruby"))
    end

    it "detects a word modification" do
      # "Hello world" → "Hello Ruby"
      # Old tokens: ["Hello", "world"]
      # New tokens: ["Hello", "Ruby"]
      # LCS: ["Hello"] — "world" modified to "Ruby"
      changes = parser.compute("Hello world", "Hello Ruby")
      expect(changes).to include(a_hash_including(
        type:        :modification,
        old_content: "world",
        new_content: "Ruby"
      ))
    end

    it "returns empty array for identical content" do
      expect(parser.compute("same text", "same text")).to be_empty
    end

    it "treats each whitespace-delimited word as a separate token" do
      # Adding a new line adds 3 tokens: newline, word, word
      # "line one\nline two" → "line one\nline two\nline three"
      # Old tokens: ["line", "one", "\n", "line", "two"]
      # New tokens: ["line", "one", "\n", "line", "two", "\n", "line", "three"]
      # Additions: 3 tokens ("\n", "line", "three")
      changes = parser.compute("line one\nline two", "line one\nline two\nline three")
      additions = changes.select { |c| c[:type] == :addition }
      expect(additions.count).to eq(3)
      expect(additions.map { |c| c[:content] }).to contain_exactly("\n", "line", "three")
    end

    it "preserves newlines as distinct tokens for paragraph detection" do
      # A blank-line paragraph break is one "\n\n" token
      changes = parser.compute("Para one", "Para one\n\nPara two")
      expect(changes).to include(a_hash_including(type: :addition, content: "\n\n"))
    end

    it "returns change hashes with :line (token index), :type, and :content keys" do
      changes = parser.compute("foo", "foo bar")
      addition = changes.find { |c| c[:type] == :addition }
      expect(addition).to include(:line, :type, :content)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/docsmith/diff/parsers/markdown_spec.rb`

Expected: FAIL — `uninitialized constant Docsmith::Diff::Parsers::Markdown`

- [ ] **Step 3: Implement the Markdown parser**

Create `lib/docsmith/diff/parsers/markdown.rb`:

```ruby
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/docsmith/diff/parsers/markdown_spec.rb`

Expected: all 7 examples pass.

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/diff/parsers/markdown.rb spec/docsmith/diff/parsers/markdown_spec.rb
git commit -m "feat(diff): add Markdown word-level diff parser"
```

---

## Task 5: Implement HTML Diff Parser

**Files:**
- Create: `lib/docsmith/diff/parsers/html.rb`
- Create: `spec/docsmith/diff/parsers/html_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/docsmith/diff/parsers/html_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Diff::Parsers::Html do
  subject(:parser) { described_class.new }

  describe "#compute" do
    it "treats an opening tag as one atomic token" do
      # "<p>Hello</p>" → "<span>Hello</span>"
      # Tokens: ["<p>", "Hello", "</p>"] vs ["<span>", "Hello", "</span>"]
      # Modifications: "<p>"→"<span>", "</p>"→"</span>"
      changes = parser.compute("<p>Hello</p>", "<span>Hello</span>")
      mods = changes.select { |c| c[:type] == :modification }
      expect(mods).to include(a_hash_including(old_content: "<p>", new_content: "<span>"))
      expect(mods).to include(a_hash_including(old_content: "</p>", new_content: "</span>"))
    end

    it "detects a new paragraph added (3 new tokens)" do
      # "<p>Hello</p>" → "<p>Hello</p><p>World</p>"
      # Old tokens: ["<p>", "Hello", "</p>"]
      # New tokens: ["<p>", "Hello", "</p>", "<p>", "World", "</p>"]
      # LCS: first 3 match — 3 additions: "<p>", "World", "</p>"
      changes = parser.compute("<p>Hello</p>", "<p>Hello</p><p>World</p>")
      additions = changes.select { |c| c[:type] == :addition }
      expect(additions.map { |c| c[:content] }).to contain_exactly("<p>", "World", "</p>")
    end

    it "detects a word change inside a tag" do
      changes = parser.compute("<p>Hello world</p>", "<p>Hello Ruby</p>")
      expect(changes).to include(a_hash_including(
        type:        :modification,
        old_content: "world",
        new_content: "Ruby"
      ))
    end

    it "treats tag with attributes as one atomic token" do
      # "<div class=\"foo\">" must be ONE token, not split on spaces inside the tag
      changes = parser.compute('<div class="foo">bar</div>', '<div class="baz">bar</div>')
      mods = changes.select { |c| c[:type] == :modification }
      expect(mods).to include(a_hash_including(
        old_content: '<div class="foo">',
        new_content: '<div class="baz">'
      ))
    end

    it "returns empty array for identical HTML" do
      html = "<p>Same content</p>"
      expect(parser.compute(html, html)).to be_empty
    end

    it "does not split tag delimiters < and > as separate tokens" do
      # If the tokenizer split on < and >, the open bracket "<" would be its own token.
      # Verify that no change content is exactly "<" or ">"
      changes = parser.compute("<p>a</p>", "<p>b</p>")
      all_content = changes.flat_map { |c| [c[:content], c[:old_content], c[:new_content]] }.compact
      expect(all_content).not_to include("<", ">")
    end

    it "returns change hashes with :line (token index), :type, and content keys" do
      changes = parser.compute("<p>foo</p>", "<p>foo</p><p>bar</p>")
      addition = changes.find { |c| c[:type] == :addition }
      expect(addition).to include(:line, :type, :content)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/docsmith/diff/parsers/html_spec.rb`

Expected: FAIL — `uninitialized constant Docsmith::Diff::Parsers::Html`

- [ ] **Step 3: Implement the HTML parser**

Create `lib/docsmith/diff/parsers/html.rb`:

```ruby
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/docsmith/diff/parsers/html_spec.rb`

Expected: all 6 examples pass.

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/diff/parsers/html.rb spec/docsmith/diff/parsers/html_spec.rb
git commit -m "feat(diff): add HTML-aware diff parser treating tags as atomic tokens"
```

---

## Task 6: Wire Parsers into Engine

**Files:**
- Modify: `lib/docsmith/diff/engine.rb`

Parsers are already required before engine in `lib/docsmith.rb` (added in Task 2, Step 1). Now update engine to use them.

- [ ] **Step 1: Write a failing test for the engine using format-aware parser**

Add to `spec/docsmith/diff/engine_spec.rb` (after the existing describe blocks):

```ruby
  describe "format-aware parser dispatch" do
    let(:md_doc) { create(:document, content: "# Hello", content_type: "markdown") }
    let(:html_doc) { create(:document, content: "<p>Hello</p>", content_type: "html") }

    let(:md_v1) { create(:document_version, document: md_doc, content: "Hello world", version_number: 1, content_type: "markdown") }
    let(:md_v2) { create(:document_version, document: md_doc, content: "Hello Ruby world", version_number: 2, content_type: "markdown") }

    let(:html_v1) { create(:document_version, document: html_doc, content: "<p>Hello</p>", version_number: 1, content_type: "html") }
    let(:html_v2) { create(:document_version, document: html_doc, content: "<p>Hello</p><p>World</p>", version_number: 2, content_type: "html") }

    it "uses Markdown parser for markdown content — detects word addition" do
      result = described_class.between(md_v1, md_v2)
      # "Hello world" → "Hello Ruby world": 1 word added ("Ruby")
      expect(result.additions).to eq(1)
      expect(result.changes.find { |c| c[:type] == :addition }[:content]).to eq("Ruby")
    end

    it "uses HTML parser for html content — treats tags as atomic tokens" do
      result = described_class.between(html_v1, html_v2)
      # "<p>Hello</p>" → "<p>Hello</p><p>World</p>": 3 token additions
      expect(result.additions).to eq(3)
    end
  end
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `bundle exec rspec spec/docsmith/diff/engine_spec.rb -e "format-aware"`

Expected: FAIL — engine still uses `Renderers::Base` for all types.

- [ ] **Step 3: Update `lib/docsmith/diff/engine.rb` to use the PARSERS map**

Replace the file with:

```ruby
# frozen_string_literal: true

module Docsmith
  module Diff
    # Computes diffs between two DocumentVersion records.
    # For markdown and html content types, a format-aware parser is used
    # (word-level for markdown, tag-atomic for html).
    # Falls back to Renderers::Base (line-level) for json and unknown types.
    class Engine
      PARSERS = {
        "markdown" => Parsers::Markdown,
        "html"     => Parsers::Html
      }.freeze

      class << self
        # @param version_a [Docsmith::DocumentVersion] the older version
        # @param version_b [Docsmith::DocumentVersion] the newer version
        # @return [Docsmith::Diff::Result]
        def between(version_a, version_b)
          content_type = version_a.content_type.to_s
          parser       = PARSERS.fetch(content_type, Renderers::Base).new
          changes      = parser.compute(version_a.content.to_s, version_b.content.to_s)

          Result.new(
            content_type: content_type,
            from_version: version_a.version_number,
            to_version:   version_b.version_number,
            changes:      changes
          )
        end
      end
    end

    # Convenience module method: Docsmith::Diff.between(v1, v2)
    def self.between(version_a, version_b)
      Engine.between(version_a, version_b)
    end
  end
end
```

- [ ] **Step 4: Run the new engine tests to verify they pass**

Run: `bundle exec rspec spec/docsmith/diff/engine_spec.rb -e "format-aware"`

Expected: 2 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/diff/engine.rb spec/docsmith/diff/engine_spec.rb
git commit -m "feat(diff): wire format-aware parsers into Engine via PARSERS dispatch map"
```

---

## Task 7: Fix Broken Count Expectations in Existing Specs

The word-level Markdown parser produces more tokens than the old line-level Base renderer. Three spec files assert specific addition counts that now need updating.

**Affected expectations** (all involve `"line one\nline two"` → `"line one\nline two\nline three"` on `content_type: "markdown"`):

Old (line-level): 1 line added  
New (word-level): 3 tokens added (`"\n"`, `"line"`, `"three"`)

**Files:**
- Modify: `spec/docsmith/diff/engine_spec.rb`
- Modify: `spec/docsmith/phase2_integration_spec.rb`
- Modify: `spec/docsmith/versionable_spec.rb`

- [ ] **Step 1: Fix `spec/docsmith/diff/engine_spec.rb`**

In the `describe ".between"` block, the test `"detects the added line"`:

```ruby
# BEFORE:
    it "detects the added line" do
      expect(result.additions).to eq(1)
      expect(result.deletions).to eq(0)
    end

# AFTER:
    it "detects token additions (word-level for markdown)" do
      # v1: "line one\nline two"   → tokens: ["line", "one", "\n", "line", "two"]
      # v2: adds "\nline three"    → 3 new tokens: "\n", "line", "three"
      expect(result.additions).to eq(3)
      expect(result.deletions).to eq(0)
    end
```

In the `describe "Docsmith::Diff.between (module convenience method)"` block:

```ruby
# BEFORE:
      expect(result.additions).to eq(1)

# AFTER:
      expect(result.additions).to eq(3)
```

- [ ] **Step 2: Run engine spec to verify**

Run: `bundle exec rspec spec/docsmith/diff/engine_spec.rb`

Expected: all examples pass.

- [ ] **Step 3: Fix `spec/docsmith/phase2_integration_spec.rb`**

```ruby
# BEFORE — "diff_from returns correct addition count":
    expect(result.additions).to eq(1)

# AFTER:
    expect(result.additions).to eq(3)
```

```ruby
# BEFORE — "Diff::Result#to_json returns valid JSON with stats":
    expect(parsed["stats"]["additions"]).to eq(1)

# AFTER:
    expect(parsed["stats"]["additions"]).to eq(3)
```

- [ ] **Step 4: Run phase2 spec to verify**

Run: `bundle exec rspec spec/docsmith/phase2_integration_spec.rb`

Expected: all 6 examples pass.

- [ ] **Step 5: Fix `spec/docsmith/versionable_spec.rb`** — two changes

**Change A:** Remove the branch describe blocks (lines 435–531). Delete the following four describe blocks entirely:

```ruby
# DELETE this entire block (lines 435–455):
  describe "#save_version! with branch:" do
    ...
  end

# DELETE this entire block (lines 457–476):
  describe "#create_branch!" do
    ...
  end

# DELETE this entire block (lines 478–500):
  describe "#branches and #active_branches" do
    ...
  end

# DELETE this entire block (lines 502–531):
  describe "#merge_branch!" do
    ...
  end
```

**Change B:** In the `describe "#diff_from"` block, update the addition count:

```ruby
# BEFORE:
      expect(result.additions).to eq(1)

# AFTER:
      expect(result.additions).to eq(3)
```

- [ ] **Step 6: Run versionable spec to verify**

Run: `bundle exec rspec spec/docsmith/versionable_spec.rb`

Expected: all examples pass (branch describe blocks gone, count updated).

- [ ] **Step 7: Run the full suite**

Run: `bundle exec rspec --format progress`

Expected: 0 failures. Note the total example count will be lower than before (branch specs deleted).

- [ ] **Step 8: Commit**

```bash
git add spec/docsmith/diff/engine_spec.rb spec/docsmith/phase2_integration_spec.rb spec/docsmith/versionable_spec.rb
git commit -m "test: update addition count assertions for word-level Markdown parser"
```

---

## Task 8: Update gemspec Description

**Files:**
- Modify: `docsmith.gemspec`

- [ ] **Step 1: Update the description to remove branching mention**

In `docsmith.gemspec`, replace the `spec.description` block:

```ruby
# BEFORE:
  spec.description = <<~DESC
    Docsmith is a full-featured document versioning layer for Ruby on Rails.

    It gives any ActiveRecord model snapshot-based versioning, multi-format diff rendering,
    inline range-anchored comments, and Git-like branching & merging — all with zero
    system dependencies.

    • Full content snapshots (HTML, Markdown, JSON) for trivial rollbacks
    • Pure-Ruby diff-lcs engine with line-level diffs and stats
    • Document-level + range-anchored comments with threading and migration
    • Branching and three-way merge support
    • Per-class configuration, auto-save with debounce, events, and a clean service-object API

    Perfect for wikis, CMS pages, API specs, legal documents, or any content that needs
    audit trails, collaboration, and version history.
  DESC

# AFTER:
  spec.description = <<~DESC
    Docsmith adds snapshot-based versioning to any ActiveRecord model with zero system dependencies.

    • Full content snapshots (HTML, Markdown, JSON) for instant rollbacks
    • Format-aware diff engine: word-level diffs for Markdown, tag-atomic diffs for HTML
    • Document-level and range-anchored comments with threading and version migration
    • Per-class configuration, debounced auto-save, lifecycle events, and a clean API

    Perfect for wikis, CMS pages, API specs, legal documents, or any content that needs
    an audit trail and inline collaboration.
  DESC
```

- [ ] **Step 2: Commit**

```bash
git add docsmith.gemspec
git commit -m "docs(gemspec): update description to reflect current feature set"
```

---

## Task 9: Write USAGE.md and Update README.md

**Files:**
- Create: `USAGE.md`
- Modify: `README.md`

- [ ] **Step 1: Create `USAGE.md`**

```markdown
# Docsmith Usage Guide

Docsmith adds snapshot-based versioning, format-aware diffs, and inline comments to any
ActiveRecord model. It stores all data in your existing database — no external services.

---

## Table of Contents

1. [Installation](#1-installation)
2. [Setup — Migration](#2-setup--migration)
3. [Setup — Include Versionable](#3-setup--include-versionable)
4. [Per-Class Configuration](#4-per-class-configuration)
5. [Global Configuration](#5-global-configuration)
6. [Saving Versions](#6-saving-versions)
7. [Auto-Save and Debounce](#7-auto-save-and-debounce)
8. [Querying Versions](#8-querying-versions)
9. [Restoring Versions](#9-restoring-versions)
10. [Tagging Versions](#10-tagging-versions)
11. [Diffs](#11-diffs)
12. [Comments](#12-comments)
13. [Events and Hooks](#13-events-and-hooks)
14. [Standalone Document API](#14-standalone-document-api)
15. [Configuration Reference](#15-configuration-reference)

---

## 1. Installation

Add to your `Gemfile`:

```ruby
gem "docsmith"
```

Then:

```bash
bundle install
```

---

## 2. Setup — Migration

Run the install generator to create the migration:

```bash
rails generate docsmith:install
rails db:migrate
```

This creates four tables:

| Table                   | Purpose                                      |
|-------------------------|----------------------------------------------|
| `docsmith_documents`    | One record per versioned model instance      |
| `docsmith_versions`     | Content snapshots (immutable)                |
| `docsmith_version_tags` | Named tags on specific versions              |
| `docsmith_comments`     | Inline and document-level comments           |

---

## 3. Setup — Include Versionable

Add `include Docsmith::Versionable` to any ActiveRecord model. Optionally configure
it with `docsmith_config`:

```ruby
class Article < ApplicationRecord
  include Docsmith::Versionable

  docsmith_config do
    content_field :body        # which column holds the document content
    content_type  :markdown    # :markdown, :html, or :json
  end
end
```

That is all you need. Docsmith automatically creates a shadow `Docsmith::Document`
record the first time a version is saved for each model instance.

---

## 4. Per-Class Configuration

`docsmith_config` accepts a block that can set any of the following keys:

```ruby
class LegalDocument < ApplicationRecord
  include Docsmith::Versionable

  docsmith_config do
    content_field     :body               # column to snapshot (default: :body)
    content_type      :html               # :markdown (default), :html, :json
    auto_save         false               # disable auto-save callback (default: true)
    debounce          60                  # seconds between auto-saves (default: 30)
    max_versions      50                  # cap on stored versions per document (default: nil = unlimited)
    content_extractor ->(r) { r.body.to_s.strip }   # override content_field with a proc
  end
end
```

**`content_extractor`** is useful when the field you want to version is not a plain
string column:

```ruby
docsmith_config do
  content_field     :body_data       # ActiveStorage attachment or JSONB column
  content_type      :markdown
  content_extractor ->(record) { record.body_data.to_plain_text }
end
```

---

## 5. Global Configuration

Set defaults for the whole app in `config/initializers/docsmith.rb`:

```ruby
Docsmith.configure do |config|
  config.default_content_field = :body
  config.default_content_type  = :markdown
  config.auto_save             = true
  config.default_debounce      = 30     # seconds
  config.max_versions          = nil    # nil = unlimited
end
```

Resolution order: **per-class `docsmith_config`** > **global `Docsmith.configure`** > **gem defaults**.

---

## 6. Saving Versions

Call `save_version!` to take an explicit snapshot:

```ruby
article = Article.find(1)
article.body = "Updated content here."
article.save!

version = article.save_version!(author: current_user, summary: "Fixed typo in intro")
# => #<Docsmith::DocumentVersion version_number: 3, content_type: "markdown", ...>
```

- Returns the new `DocumentVersion` record.
- Returns `nil` if the content has not changed since the last snapshot.
- Raises `Docsmith::InvalidContentField` if `content_field` returns a non-String and
  no `content_extractor` is configured.

---

## 7. Auto-Save and Debounce

When `auto_save: true` (the default), Docsmith hooks into ActiveRecord's `after_save`
callback and automatically takes a snapshot after every model save — subject to the
debounce window.

```ruby
article.body = "New draft"
article.save!     # triggers auto_save_version! internally
```

The **debounce** prevents a snapshot from being created if another snapshot was already
taken within the last N seconds (default: 30). This avoids flooding the version history
when a user is rapidly typing and saving.

You can also call `auto_save_version!` directly:

```ruby
article.auto_save_version!(author: current_user)
```

To disable auto-save for a class:

```ruby
docsmith_config { auto_save false }
```

---

## 8. Querying Versions

```ruby
# All versions, ordered by version_number ascending
article.versions
# => ActiveRecord::Relation<Docsmith::DocumentVersion>

# Latest version
article.current_version
# => #<Docsmith::DocumentVersion version_number: 5, ...>

# Specific version by number
article.version(3)
# => #<Docsmith::DocumentVersion version_number: 3, ...>

# Inspect content
article.version(2).content          # => "Body text at v2"
article.version(2).content_type     # => "markdown"
article.version(2).author           # => #<User id: 1, ...>
article.version(2).change_summary   # => "Second draft"
article.version(2).created_at       # => 2026-03-01 14:22:00 UTC

# Render a version's content
article.version(2).render(:html)    # => "<p>Body text at v2</p>"
article.version(2).render(:json)    # => '{"version":2,"content":"..."}'
```

---

## 9. Restoring Versions

Restore creates a **new version** whose content matches an older snapshot. It never
mutates existing version records.

```ruby
restored = article.restore_version!(2, author: current_user)
# => #<Docsmith::DocumentVersion version_number: 6, change_summary: "Restored from v2", ...>

article.reload.body   # => the body content from v2
```

- The model's `content_field` column is updated via `update_column` (bypasses callbacks
  to avoid a duplicate auto-save).
- Fires the `:version_restored` event hook (see §13).
- Raises `Docsmith::VersionNotFound` if the version number does not exist.

---

## 10. Tagging Versions

Tags are named pointers to specific versions, unique per document.

```ruby
# Create a tag
article.tag_version!(3, name: "v1.0-release", author: current_user)

# Look up a version by tag name
v = article.tagged_version("v1.0-release")
# => #<Docsmith::DocumentVersion version_number: 3, ...>

# List tag names on a version
article.version_tags(3)
# => ["v1.0-release", "stable"]
```

- Raises `Docsmith::TagAlreadyExists` if the name is already used on this document.
- Raises `Docsmith::VersionNotFound` if the version number does not exist.

**Interaction with `max_versions`:** Tagged versions are never pruned automatically.
If all versions are tagged and a prune would be needed, `Docsmith::MaxVersionsExceeded`
is raised.

---

## 11. Diffs

Docsmith computes diffs between any two versions. The parser used depends on the
document's `content_type`.

### Diff from version N to current

```ruby
result = article.diff_from(1)
# => #<Docsmith::Diff::Result from_version: 1, to_version: 5, ...>

result.additions   # => integer count of added tokens
result.deletions   # => integer count of removed tokens
result.to_html     # => HTML string with <ins>/<del> markup
result.to_json     # => JSON string with stats and changes array
```

### Diff between two named versions

```ruby
result = article.diff_between(2, 4)
```

### Format-aware parsers

| `content_type` | Parser | Token unit |
|----------------|--------|-----------|
| `markdown`     | `Docsmith::Diff::Parsers::Markdown` | Each whitespace-delimited word; newline runs are one token |
| `html`         | `Docsmith::Diff::Parsers::Html` | Each HTML tag (including attributes) is one token; words in text are separate tokens |
| `json`         | `Docsmith::Diff::Renderers::Base` | Line-level (whole lines) |

**Markdown example:**

```ruby
# v1 content: "The quick brown fox"
# v2 content: "The quick red fox"
result = article.diff_between(1, 2)
result.changes
# => [{ type: :modification, line: 3, old_content: "brown", new_content: "red" }]
result.additions  # => 0
result.deletions  # => 0
```

**HTML example:**

```ruby
# v1 content: "<p>Hello world</p>"
# v2 content: "<p>Hello world</p><p>New paragraph</p>"
# old tokens: ["<p>", "Hello", "world", "</p>"]
# new tokens: ["<p>", "Hello", "world", "</p>", "<p>", "New", "paragraph", "</p>"]
# LCS: first 4 tokens match exactly → 4 additions: "<p>", "New", "paragraph", "</p>"
result = article.diff_between(1, 2)
result.additions  # => 4
```

### to_html output

```ruby
result.to_html
# => '<div class="docsmith-diff">
#      <ins class="docsmith-addition">Ruby</ins>
#      <del class="docsmith-deletion">Python</del>
#    </div>'
```

### to_json output

```ruby
JSON.parse(result.to_json)
# => {
#   "content_type" => "markdown",
#   "from_version" => 1,
#   "to_version"   => 3,
#   "stats"        => { "additions" => 2, "deletions" => 1 },
#   "changes"      => [
#     { "type" => "addition",      "position" => { "line" => 5 }, "content" => "Ruby" },
#     { "type" => "deletion",      "position" => { "line" => 3 }, "content" => "Python" },
#     { "type" => "modification",  "position" => { "line" => 7 }, "old_content" => "foo", "new_content" => "bar" }
#   ]
# }
```

---

## 12. Comments

Comments can be attached to a specific version. They are either **document-level** (no
position) or **range-anchored** (tied to a character offset range).

### Add a comment

```ruby
# Document-level comment
comment = article.add_comment!(
  version: 2,
  body:    "This section needs a citation.",
  author:  current_user
)
comment.anchor_type  # => "document"

# Range-anchored (inline) comment — offsets into the version's content string
comment = article.add_comment!(
  version: 2,
  body:    "Cite this claim.",
  author:  current_user,
  anchor:  { start_offset: 42, end_offset: 78 }
)
comment.anchor_type                     # => "range"
comment.anchor_data["start_offset"]     # => 42
comment.anchor_data["anchored_text"]    # => the substring from offset 42–78
```

### Thread replies

```ruby
reply = article.add_comment!(
  version: 2,
  body:    "Good point, fixing now.",
  author:  other_user,
  parent:  comment
)
comment.replies   # => [reply]
reply.parent      # => comment
```

### Query comments

```ruby
# All comments across all versions (AR relation)
article.comments

# Comments on a specific version
article.comments_on(version: 2)

# Filter by type
article.comments_on(version: 2, type: :range)     # inline only
article.comments_on(version: 2, type: :document)  # document-level only

# Unresolved comments across all versions
article.unresolved_comments
```

### Resolve a comment

```ruby
Docsmith::Comments::Manager.resolve!(comment, by: current_user)
comment.reload.resolved     # => true
comment.resolved_by         # => current_user
comment.resolved_at         # => Time
```

### Migrate comments between versions

When a new version is saved, document-level comments from the previous version can be
migrated forward:

```ruby
article.migrate_comments!(from: 2, to: 3)
# Copies document-level (non-range) comments from v2 to v3.
# Range comments are not migrated — their offsets may no longer be valid.
```

---

## 13. Events and Hooks

Docsmith fires synchronous events you can subscribe to via `Docsmith.configure`.

```ruby
Docsmith.configure do |config|
  config.on(:version_created) do |event|
    Rails.logger.info "[Docsmith] v#{event.version.version_number} saved on #{event.document.title}"
    AuditLog.create!(action: "version_created", record: event.record)
  end

  config.on(:version_restored) do |event|
    Rails.logger.info "[Docsmith] Restored to v#{event.version.version_number}"
  end

  config.on(:version_tagged) do |event|
    Rails.logger.info "[Docsmith] Tagged v#{event.version.version_number} as '#{event.tag_name}'"
  end
end
```

**Event payload** (`event` is a `Docsmith::Events::Event`):

| Field          | Type                                 | Always present |
|----------------|--------------------------------------|----------------|
| `event.record` | The originating AR model (or Document if standalone) | yes |
| `event.document` | `Docsmith::Document`              | yes |
| `event.version` | `Docsmith::DocumentVersion`        | yes |
| `event.author` | whatever you passed as `author:`     | yes |
| `event.tag_name` | String (`:version_tagged` only)   | no  |
| `event.from_version` | DocumentVersion (`:version_restored` only) | no |

Hooks fire before `ActiveSupport::Notifications` so they are synchronous and blocking.
Keep hooks fast.

---

## 14. Standalone Document API

`Docsmith::Versionable` is a convenience wrapper. You can use `Docsmith::Document` and
`Docsmith::VersionManager` directly without any model mixin:

```ruby
doc = Docsmith::Document.create!(
  title:        "My API Spec",
  content:      "# Version 1\n\nInitial spec.",
  content_type: "markdown"
)

v1 = Docsmith::VersionManager.save!(doc, author: nil, summary: "Initial draft")
doc.update_column(:content, "# Version 1\n\nRevised spec.")
v2 = Docsmith::VersionManager.save!(doc, author: nil, summary: "Revised intro")

# Diff
result = Docsmith::Diff.between(v1, v2)
result.additions   # => number of added tokens
result.to_html     # => HTML diff markup

# Restore
Docsmith::VersionManager.restore!(doc, version: 1, author: nil)
doc.reload.content   # => "# Version 1\n\nInitial spec."

# Tag
Docsmith::VersionManager.tag!(doc, version: 1, name: "golden", author: nil)
```

---

## 15. Configuration Reference

| Key | Default | Description |
|-----|---------|-------------|
| `default_content_field` | `:body` | Column to snapshot when no per-class override |
| `default_content_type` | `:markdown` | Content type for new documents |
| `auto_save` | `true` | Enable after_save auto-snapshot |
| `default_debounce` | `30` | Seconds between auto-saves |
| `max_versions` | `nil` | Max snapshots per document; `nil` = unlimited |
| `content_extractor` | `nil` | Global proc overriding `content_field` |
| `table_prefix` | `"docsmith"` | Table name prefix |
| `diff_context_lines` | `3` | Context lines in diff output |

**Error classes:**

| Class | Raised when |
|-------|-------------|
| `Docsmith::InvalidContentField` | `content_field` returns a non-String |
| `Docsmith::VersionNotFound` | Requested version number does not exist |
| `Docsmith::TagAlreadyExists` | Tag name already used on this document |
| `Docsmith::MaxVersionsExceeded` | All versions are tagged and pruning is blocked |
```

- [ ] **Step 2: Verify the file was created correctly**

Run: `wc -l USAGE.md`

Expected: > 300 lines (it's a substantial file).

- [ ] **Step 3: Update `README.md`**

Replace the entire README.md with:

```markdown
# Docsmith

Docsmith adds snapshot-based versioning, format-aware diffs, and inline comments to any
ActiveRecord model — with zero system dependencies.

## Features

- **Full content snapshots** for HTML, Markdown, and JSON — instant rollback to any version
- **Format-aware diffs** — word-level diffs for Markdown; HTML tags treated as atomic tokens
- **Inline and document-level comments** with threading, resolution, and version migration
- **Debounced auto-save** with per-class and global configuration
- **Lifecycle events** — hook into version_created, version_restored, version_tagged
- **Clean service API** — works standalone without any model mixin

## Quick Start

```ruby
# Gemfile
gem "docsmith"
```

```bash
rails generate docsmith:install
rails db:migrate
```

```ruby
class Article < ApplicationRecord
  include Docsmith::Versionable
  docsmith_config { content_field :body; content_type :markdown }
end

article.body = "New draft"
article.save!
article.save_version!(author: current_user, summary: "First draft")

result = article.diff_from(1)
result.additions   # word-level count for markdown
result.to_html     # <ins>/<del> markup
```

## Documentation

See **[USAGE.md](USAGE.md)** for full documentation including:

- Installation and migration
- Per-class and global configuration
- Saving, querying, and restoring versions
- Version tagging
- Format-aware diffs (Markdown and HTML parsers)
- Inline and document-level comments
- Events and hooks
- Standalone Document API
- Configuration reference

## Development

```bash
bin/setup
bundle exec rspec    # run tests
bin/console          # interactive console
```

## License

MIT — see [LICENSE.txt](LICENSE.txt).
```

- [ ] **Step 4: Final full test run**

Run: `bundle exec rspec --format documentation`

Expected: 0 failures. Review the output to confirm parser specs, engine dispatch specs, and all integration specs pass.

- [ ] **Step 5: Commit documentation**

```bash
git add USAGE.md README.md
git commit -m "docs: write verbose USAGE.md and update README with feature overview"
```

---

## Self-Review

**Spec coverage check:**
- ✅ Markdown word-level parser → Task 4
- ✅ HTML tag-atomic parser → Task 5
- ✅ Engine dispatch for markdown/html → Task 6
- ✅ Remove all branch lib code → Task 1 + 2
- ✅ Remove branch schema → Task 3
- ✅ Remove branch specs → Task 1 + 7
- ✅ Fix broken count expectations → Task 7
- ✅ USAGE.md created → Task 9
- ✅ README.md updated → Task 9

**Placeholder scan:** None — all code blocks show complete, runnable Ruby.

**Type consistency:**
- `Parsers::Markdown#compute` and `Parsers::Html#compute` both return `Array<Hash>` with keys `:type`, `:line`, `:content` / `:old_content` / `:new_content` — matches what `Renderers::Base#compute` returns and what `Result`, `render_html`, and `serialize_change` consume.
- `Engine::PARSERS` references `Parsers::Markdown` and `Parsers::Html` — both defined before engine is loaded (require order in `lib/docsmith.rb` established in Task 2, Step 1).
- `VersionManager.save!` signature after edit: `(document, author:, summary: nil, config: nil)` — matches all call sites in versionable.rb and specs.
