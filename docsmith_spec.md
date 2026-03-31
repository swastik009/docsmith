# Docsmith — Ruby Gem Specification

## Overview
Docsmith is a plug-and-play document version manager gem for Rails. It provides full snapshot-based versioning, multi-format diff rendering, inline commenting, and branch/merge — all via ActiveRecord.

**Gem name:** `docsmith`
**Module namespace:** `Docsmith`
**Ruby:** >= 3.1
**Rails:** >= 7.0
**License:** MIT

---

## Design Decisions

**Why full snapshots over deltas?** Three content types (HTML, Markdown, JSON)
would need three different delta formats. Full snapshots keep storage simple,
make rollback trivial (just copy), and let us swap diff algorithms per content
type without migrating data. Storage cost is negligible for text documents.

**Why diff-lcs over Diffy?** Diffy wraps Unix `diff` binary — adds a system
dependency for ~70% coverage across our content types. diff-lcs is pure Ruby,
already a transitive dependency via RSpec, and gives us full programmatic
control over change objects for stats, comment anchoring, and merge detection.

**Why not PaperTrail/Logidze/Audited?** Those are model-level auditing gems.
They track attribute changes on any AR model. Docsmith treats documents as
first-class citizens with content-type-aware diffing, commenting, branching,
and multi-format rendering. Different problem space.

**Config precedence:** per-class `docsmith_config` > global `Docsmith.configure` > gem defaults.
Any setting not specified at a level falls through to the next level.

---

## Architecture Summary

| Concern | Approach |
|---|---|
| Storage | ActiveRecord (PostgreSQL/MySQL/SQLite) |
| Document types | Rich text/HTML, Markdown, Structured JSON |
| Versioning | Full snapshots, diff computed on read |
| Version creation | Auto-save with configurable debounce |
| Diffing | diff-lcs (pure Ruby). Snapshots stored, diffs computed on read. Custom renderers per content type can be added later — start with line-level for all types |
| Comments | Document-level + range-anchored inline annotations |
| User identity | Polymorphic association (`author_type` / `author_id`) |
| Integration | Mixin (`include Docsmith::Versionable`) + Service objects |
| DB setup | `rails generate docsmith:install` |
| Events | Callback hooks + ActiveSupport::Notifications |
| Output formats | HTML and JSON |

---

## Phase 1 — Core Versioning (snapshots, restore, tags)

### Database Tables

```
docsmith_documents
  id              :bigint, PK
  title           :string
  content_type    :string          # "html", "markdown", "json"
  current_version :integer, default: 0
  metadata        :jsonb, default: {}
  created_at      :datetime
  updated_at      :datetime

docsmith_versions
  id              :bigint, PK
  document_id     :bigint, FK -> docsmith_documents
  version_number  :integer
  content         :text             # full snapshot
  content_type    :string           # inherited from document at save time
  author_type     :string           # polymorphic
  author_id       :bigint           # polymorphic
  change_summary  :string, nullable
  metadata        :jsonb, default: {}
  created_at      :datetime

  index: [document_id, version_number], unique: true
  index: [author_type, author_id]

docsmith_version_tags
  id              :bigint, PK
  version_id      :bigint, FK -> docsmith_versions
  name            :string           # e.g. "v2.1-final"
  author_type     :string
  author_id       :bigint
  created_at      :datetime

  index: [version_id, name], unique: true
```

### Mixin API (Phase 1)

```ruby
class Article < ApplicationRecord
  include Docsmith::Versionable

  # Per-class config (all optional — falls through to global config if not set)
  # Per-class ALWAYS takes precedence over global config
  docsmith_config do
    content_field   :body                    # field to version
    content_type    :html                    # overrides global default (:markdown)
    auto_save       true
    debounce        60.seconds               # overrides global default (30.seconds)
    max_versions    nil                      # nil = unlimited
  end
end

# Resolution order: per-class config > global config > gem defaults
# If Article sets content_type: :html but not debounce,
# it uses :html for content_type and global config value for debounce

# Usage
article = Article.find(1)

# Saving versions
article.save_version!(author: current_user, summary: "Fixed intro")
article.save_version!(author: current_user)   # summary optional

# Auto-save (respects debounce)
article.auto_save_version!(author: current_user)
# Returns false if debounce period hasn't elapsed

# Reading versions
article.versions                    # => ActiveRecord relation of Docsmith::Version
article.versions.count              # => 5
article.current_version             # => Docsmith::Version
article.version(3)                  # => Docsmith::Version for v3

# Restoring
article.restore_version!(3, author: current_user)
# Creates NEW version (v6) with content from v3. Never mutates history.

# Tagging
article.tag_version!(3, name: "v1.0-release", author: current_user)
article.tagged_version("v1.0-release")  # => Docsmith::Version
article.version_tags(3)                 # => ["v1.0-release"]
```

### Service Object API (Phase 1)

```ruby
doc = Docsmith::Document.create!(
  title: "API Spec",
  content: "# Hello",
  content_type: :markdown
)

# Or wrap an existing record
doc = Docsmith::Document.from_record(article, field: :body)

Docsmith::VersionManager.save!(doc, author: current_user, summary: "Initial")
Docsmith::VersionManager.restore!(doc, version: 3, author: current_user)
Docsmith::VersionManager.tag!(doc, version: 3, name: "v1.0", author: current_user)
```

### Events (Phase 1)

```ruby
# Callback hooks
Docsmith.configure do |config|
  config.on(:version_created) do |event|
    # event.document, event.version, event.author
  end
  config.on(:version_restored) do |event|
    # event.document, event.from_version, event.to_version, event.author
  end
  config.on(:version_tagged) do |event|
    # event.version, event.tag_name, event.author
  end
end

# ActiveSupport::Notifications (always emitted)
ActiveSupport::Notifications.subscribe("version_created.docsmith") do |event|
  # event.payload[:document], [:version], [:author]
end
```

### Generator (Phase 1)

```bash
rails generate docsmith:install
# Creates:
#   db/migrate/TIMESTAMP_create_docsmith_tables.rb
#   config/initializers/docsmith.rb
```

---

## Phase 2 — HTML/JSON Rendering & Diff Views

### Diff Engine

Uses `diff-lcs` (pure Ruby, zero system dependencies) for all diffing.
All content types use line-level diffing for v1. Content-type-specific
renderers (DOM-aware for HTML, key-path for JSON) can be added later
without changing storage — that's the benefit of full snapshots.

```ruby
# Compute diff between any two versions
diff = Docsmith::Diff.between(version_a, version_b)

diff.content_type   # => "markdown"
diff.additions       # => integer count
diff.deletions       # => integer count
diff.changes         # => array of change objects

# Render diff
diff.to_html         # => HTML string with inline highlighting
diff.to_json         # => structured JSON diff

# Compare with current
diff = article.diff_from(3)           # version 3 vs current
diff = article.diff_between(2, 5)     # version 2 vs version 5
```

### Content-Type Diff Renderers

v1: All content types use the same line-level diff renderer via diff-lcs.
For JSON, content is pretty-printed before diffing so key changes show
as line changes. Custom renderers can be registered later.

```ruby
# v1: single renderer handles all types (line-level via diff-lcs)
Docsmith::DiffRenderer::Base       # line-level, works for all types

# Future: content-type-specific renderers (register when needed)
# Docsmith::DiffRenderer::Html     # DOM-aware, tag-level
# Docsmith::DiffRenderer::Json     # key-path aware, value comparison

# Custom renderer registration (available now, use when ready)
Docsmith.configure do |config|
  config.register_diff_renderer(:custom_type, MyCustomRenderer)
end
```

### Document Rendering

```ruby
version = article.version(3)

# Render document content (not diff) in output format
version.render(:html)   # => HTML representation
version.render(:json)   # => JSON representation

# With options
version.render(:html, theme: :github, line_numbers: true)
```

### Diff JSON Structure

```json
{
  "content_type": "markdown",
  "from_version": 2,
  "to_version": 5,
  "stats": { "additions": 12, "deletions": 3, "modifications": 5 },
  "changes": [
    {
      "type": "addition",
      "position": { "line": 15 },
      "content": "New paragraph text"
    },
    {
      "type": "modification",
      "position": { "line": 8 },
      "old_content": "Original text",
      "new_content": "Updated text"
    }
  ]
}
```

---

## Phase 3 — Comments & Inline Annotations

**Complexity note:** Document-level comments with threading are straightforward.
Range-anchored inline annotations add significant complexity (anchor migration,
orphan detection). Build document-level first, add range anchoring second.
If range anchoring proves too complex, ship without it — document-level
comments are still valuable.

### Database Tables

```
docsmith_comments
  id              :bigint, PK
  version_id      :bigint, FK -> docsmith_versions
  parent_id       :bigint, FK -> docsmith_comments, nullable  # threading
  author_type     :string
  author_id       :bigint
  body            :text
  anchor_type     :string           # "document" or "range"
  anchor_data     :jsonb, default: {}
  # For range anchors: { start_offset: 45, end_offset: 72, content_hash: "abc123" }
  resolved        :boolean, default: false
  resolved_by_type :string, nullable
  resolved_by_id  :bigint, nullable
  resolved_at     :datetime, nullable
  created_at      :datetime
  updated_at      :datetime

  index: [version_id]
  index: [parent_id]
  index: [author_type, author_id]
```

### Comment API

```ruby
# Document-level comment
article.add_comment!(
  version: 3,
  body: "Looks good overall",
  author: current_user
)

# Inline annotation (range-anchored)
article.add_comment!(
  version: 3,
  body: "This needs a citation",
  author: current_user,
  anchor: { start_offset: 45, end_offset: 72 }
)

# Reply to comment (threading)
article.add_comment!(
  version: 3,
  body: "Added the citation",
  author: current_user,
  parent: original_comment
)

# Resolve
comment.resolve!(by: current_user)

# Query
article.comments                        # all comments across versions
article.comments_on(version: 3)         # comments on specific version
article.comments_on(version: 3, type: :range)   # only inline annotations
article.unresolved_comments             # across all versions

# Comment migration across versions
article.migrate_comments!(from: 3, to: 4)
# Attempts to re-anchor range comments to new version content
# Uses content_hash for fuzzy matching when offsets shift
```

### Anchor Strategy for Range Comments

```
When content changes between versions:
1. Try exact offset match
2. If content at offset differs, use content_hash to find relocated text
3. If text is gone, mark comment as "orphaned" (still visible, flagged)

anchor_data schema:
{
  start_offset: Integer,       # character offset from document start
  end_offset: Integer,         # character offset end
  content_hash: String,        # SHA256 of the anchored text snippet
  anchored_text: String,       # the original selected text (for display)
  status: "active" | "drifted" | "orphaned"
}
```

### Events (Phase 3)

```ruby
# Additional hooks
config.on(:comment_added)    { |e| }
config.on(:comment_resolved) { |e| }
config.on(:comment_orphaned) { |e| }

# AS::Notifications
"comment_added.docsmith"
"comment_resolved.docsmith"
```

---

## Phase 4 — Branching & Merging

**Complexity note:** This is the hardest phase. Three-way merge with
conflict detection is non-trivial. For v1, start with branch creation
and simple fast-forward merges (branch head replaces main when main
hasn't changed since fork). Full three-way merge with conflict
resolution can come in v1.1+.

### Database Tables

```
docsmith_branches
  id              :bigint, PK
  document_id     :bigint, FK -> docsmith_documents
  name            :string
  source_version  :bigint, FK -> docsmith_versions  # where it forked from
  head_version    :bigint, FK -> docsmith_versions, nullable
  author_type     :string
  author_id       :bigint
  status          :string           # "active", "merged", "abandoned"
  merged_at       :datetime, nullable
  created_at      :datetime
  updated_at      :datetime

  index: [document_id, name], unique: true
```

### Branch API

```ruby
# Create branch from version
branch = article.create_branch!(
  name: "experimental-intro",
  from_version: 3,
  author: current_user
)

# Save to branch
article.save_version!(author: current_user, branch: branch)

# List branches
article.branches                   # => all branches
article.active_branches            # => non-merged, non-abandoned

# Read branch
branch.versions                    # => versions on this branch
branch.head                        # => latest version on branch
branch.source_version              # => version it forked from

# Diff branch against main
diff = branch.diff_from_source     # head vs fork point
diff = branch.diff_against_current # head vs current main version

# Merge
merge_result = article.merge_branch!(branch, author: current_user)
merge_result.success?              # => true/false
merge_result.conflicts             # => [] or array of conflict descriptions
merge_result.merged_version        # => new Docsmith::Version if success

# Conflict handling (content-type specific)
# For markdown: line-level conflict markers (like git)
# For JSON: key-path conflicts listed
# For HTML: block-level conflicts
```

### Merge Strategy

```
1. Three-way merge: source_version (common ancestor), branch head, main head
2. Content-type specific merger:
   - Markdown: line-based three-way merge
   - JSON: deep merge with conflict detection on same-key changes
   - HTML: block-level merge (paragraph/div granularity)
3. If auto-merge succeeds: create new version on main
4. If conflicts: return MergeResult with conflicts, no version created
5. Manual resolution: user edits content, calls save_version! normally
```

### Events (Phase 4)

```ruby
config.on(:branch_created) { |e| }
config.on(:branch_merged)  { |e| }
config.on(:merge_conflict) { |e| }

"branch_created.docsmith"
"branch_merged.docsmith"
"merge_conflict.docsmith"
```

---

## Gem File Structure

```
docsmith/
├── docsmith.gemspec
├── Gemfile
├── README.md
├── LICENSE
├── Rakefile
├── lib/
│   ├── docsmith.rb                          # main entry, autoloads
│   ├── docsmith/
│   │   ├── version.rb                       # gem version constant
│   │   ├── configuration.rb                 # Docsmith.configure block
│   │   ├── errors.rb                        # custom error classes
│   │   ├── versionable.rb                   # ActiveRecord mixin
│   │   ├── document.rb                      # standalone document model
│   │   ├── version_record.rb               # Docsmith::Version AR model
│   │   ├── version_tag.rb                   # Docsmith::VersionTag AR model
│   │   ├── version_manager.rb              # service object for versioning
│   │   ├── auto_save.rb                     # debounce logic
│   │   ├── diff/
│   │   │   ├── engine.rb                    # Docsmith::Diff.between
│   │   │   ├── result.rb                    # diff result object
│   │   │   └── renderers/
│   │   │       ├── base.rb                  # line-level via diff-lcs (handles all types in v1)
│   │   │       └── registry.rb             # renderer registration for future custom renderers
│   │   ├── comments/
│   │   │   ├── comment.rb                   # AR model
│   │   │   ├── manager.rb                   # service object
│   │   │   ├── anchor.rb                    # range anchor logic
│   │   │   └── migrator.rb                  # cross-version migration
│   │   ├── branches/
│   │   │   ├── branch.rb                    # AR model
│   │   │   ├── manager.rb                   # create/merge service
│   │   │   └── merger.rb                    # three-way merge logic
│   │   ├── events/
│   │   │   ├── hook_registry.rb             # callback hooks
│   │   │   ├── notifier.rb                  # AS::Notifications wrapper
│   │   │   └── event.rb                     # event payload object
│   │   └── rendering/
│   │       ├── html_renderer.rb
│   │       └── json_renderer.rb
│   └── generators/
│       └── docsmith/
│           └── install/
│               ├── install_generator.rb
│               └── templates/
│                   ├── create_docsmith_tables.rb.erb
│                   └── docsmith_initializer.rb.erb
├── spec/
│   ├── spec_helper.rb
│   ├── docsmith/
│   │   ├── versionable_spec.rb
│   │   ├── version_manager_spec.rb
│   │   ├── auto_save_spec.rb
│   │   ├── diff/
│   │   │   ├── engine_spec.rb
│   │   │   └── renderers/
│   │   │       └── base_renderer_spec.rb
│   │   ├── comments/
│   │   │   ├── comment_spec.rb
│   │   │   ├── manager_spec.rb
│   │   │   └── migrator_spec.rb
│   │   └── branches/
│   │       ├── branch_spec.rb
│   │       ├── manager_spec.rb
│   │       └── merger_spec.rb
│   └── support/
│       ├── schema.rb                        # test DB schema
│       └── models.rb                        # test AR models
└── .rspec
```

---

## Global Configuration

Global config sets defaults for all models. Per-class `docsmith_config`
blocks override these. Resolution: per-class > global > gem defaults.

```ruby
# config/initializers/docsmith.rb
Docsmith.configure do |config|
  # Gem defaults (shown here) — global config overrides these
  # Per-class docsmith_config blocks override global config
  config.default_content_type = :markdown    # gem default: :markdown
  config.default_debounce     = 30.seconds   # gem default: 30.seconds
  config.max_versions         = nil          # gem default: nil (unlimited)
  config.auto_save            = true         # gem default: true
  config.default_content_field = :body       # gem default: :body

  # Table name prefix (if needed)
  config.table_prefix = "docsmith"

  # Diff rendering defaults
  config.diff_context_lines = 3              # lines of context in diffs

  # Event hooks
  config.on(:version_created) { |event| }
  config.on(:version_restored) { |event| }
  config.on(:version_tagged) { |event| }
  config.on(:comment_added) { |event| }
  config.on(:branch_created) { |event| }
  config.on(:branch_merged) { |event| }
end
```

---

## Dependencies

```ruby
# gemspec
spec.add_dependency "activerecord", ">= 7.0"
spec.add_dependency "activesupport", ">= 7.0"
spec.add_dependency "diff-lcs", "~> 1.5"       # pure Ruby diffing, zero system deps
# Note: diffy was considered but adds Unix diff binary dependency
# for ~70% coverage across content types. diff-lcs is pure Ruby,
# already a transitive dep via rspec, and gives full control over
# rendering. Custom renderers can be swapped in per content type later.

spec.add_development_dependency "rspec", "~> 3.12"
spec.add_development_dependency "sqlite3"
spec.add_development_dependency "factory_bot", "~> 6.0"
spec.add_development_dependency "rubocop", "~> 1.50"
```

---

## Claude Code Usage Instructions

### How to use this spec

Feed each phase to Claude Code separately:

```
Phase 1: "Build the Docsmith gem Phase 1 from this spec: [paste Phase 1 section]"
Phase 2: "Add Phase 2 (diff & rendering) to the existing Docsmith gem: [paste Phase 2]"
Phase 3: "Add Phase 3 (comments) to Docsmith: [paste Phase 3]"
Phase 4: "Add Phase 4 (branching & merging) to Docsmith: [paste Phase 4]"
```

Each phase should include its database tables, API, events, and tests.
Always include the file structure section for context on where files go.

### Key constraints for Claude Code
- Every public method must have RDoc documentation
- Every class must have corresponding spec file
- Use `frozen_string_literal: true` in all Ruby files
- Follow Ruby community style guide
- No monkey-patching of core classes
- All ActiveRecord queries must be scope-based (no raw SQL)
- Events must fire both hooks AND AS::Notifications for every action
