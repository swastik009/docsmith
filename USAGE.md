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
