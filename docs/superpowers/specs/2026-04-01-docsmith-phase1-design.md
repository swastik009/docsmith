# Docsmith Phase 1 — Core Versioning Design

**Date:** 2026-04-01
**Scope:** Phase 1 only — snapshots, restore, tags. No diff rendering, comments, or branching.
**Status:** Approved

---

## Background

Docsmith is a plug-and-play document version manager gem for Rails. Phase 1 establishes the
storage model, the `Versionable` mixin, the standalone `Document` API, and the events system.
All later phases build on top of this foundation without changing the core tables.

**Key design decisions carried in from spec:**
- Full snapshots (not deltas) — storage is simple, rollback is trivial, diff algorithm is swappable later.
- Pure-Ruby `diff-lcs` — no system dependencies (Phase 2).
- Config precedence: per-class `docsmith_config` > global `Docsmith.configure` > gem defaults.

---

## Section 1: Database Schema

### `docsmith_documents`

The central record for every versioned document, whether created standalone or via the mixin.

```
docsmith_documents
  id                :bigint, PK
  title             :string
  content           :text                    # live content field; save_version! snapshots from here
  content_type      :string                  # "html", "markdown", "json"
  versions_count    :integer, default: 0     # renamed from current_version (naming collision avoided)
  last_versioned_at :datetime                # tracks debounce window for auto_save_version!
  subject_type      :string                  # polymorphic — set when created via Versionable mixin
  subject_id        :bigint                  # polymorphic — the originating AR record's id
  metadata          :jsonb, default: {}
  created_at        :datetime
  updated_at        :datetime

  index: [subject_type, subject_id]
```

### `docsmith_versions`

Full content snapshots. Diffs are computed on read (Phase 2), never stored.

```
docsmith_versions
  id              :bigint, PK
  document_id     :bigint, FK -> docsmith_documents
  version_number  :integer                   # 1-indexed, sequential per document
  content         :text                      # full snapshot at save time
  content_type    :string                    # inherited from document at save time
  author_type     :string                    # polymorphic author
  author_id       :bigint
  change_summary  :string, nullable
  metadata        :jsonb, default: {}
  created_at      :datetime

  index: [document_id, version_number], unique: true
  index: [author_type, author_id]
```

**AR model class:** `Docsmith::DocumentVersion` (`self.table_name = "docsmith_versions"`)
Note: class is `DocumentVersion` (not `Version`) to avoid collision with `lib/docsmith/version.rb`
which holds the `Docsmith::VERSION` gem constant.

### `docsmith_version_tags`

```
docsmith_version_tags
  id              :bigint, PK
  document_id     :bigint, FK -> docsmith_documents  # denormalized for unique constraint
  version_id      :bigint, FK -> docsmith_versions
  name            :string
  author_type     :string
  author_id       :bigint
  created_at      :datetime

  index: [document_id, name], unique: true           # tag names are unique per document
  index: [version_id]
```

`document_id` is denormalized (also reachable via `version.document_id`) to allow a DB-level
unique constraint on `[document_id, name]`. This enforces that a tag name like "v1.0-release"
can only exist once across all versions of a document.

---

## Section 2: Mixin API & Behavior Contracts

### Including the mixin

```ruby
class Article < ApplicationRecord
  include Docsmith::Versionable

  docsmith_config do
    content_field     :body           # attribute to snapshot — must return a plain String
    content_type      :html           # :html, :markdown, :json
    auto_save         true
    debounce          60.seconds      # overrides global default
    max_versions      nil             # nil = unlimited
    content_extractor nil             # optional: ->(record) { record.body.to_html }
  end
end
```

Every key in `docsmith_config` is optional. Resolution order for **every** setting, without
exception:

```
per-class docsmith_config  →  global Docsmith.configure  →  gem defaults
```

Resolution happens at read time (when a setting is accessed), not at definition time.
Changing global config after class definition takes effect for any key the class does not override.

### How the mixin hooks into ActiveRecord

1. Registers an `after_save` callback that calls `auto_save_version!` when `auto_save: true`.
2. The shadow `Docsmith::Document` row is created **lazily** on the first `save_version!` /
   `auto_save_version!` call via `find_or_create_by(subject: self)`.
3. The shadow document is cached in `@docsmith_document` after first lookup to avoid repeated queries.

### Public method contracts

```ruby
# Creates a new DocumentVersion snapshot.
# Returns the DocumentVersion on success.
# Returns nil if content is identical to the latest version (simple string == check for v1).
# Raises Docsmith::InvalidContentField if content_field does not return a String
#   (unless content_extractor is configured — its result is used instead).
article.save_version!(author: user, summary: "Fixed intro")
article.save_version!(author: user)   # summary is optional

# Debounced auto-save. Returns nil if debounce window has not elapsed OR content is unchanged.
# Returns the DocumentVersion on success. Both skip reasons return nil (no distinction needed).
article.auto_save_version!(author: user)

# AR relation of all DocumentVersions for this record. Orderable and chainable.
article.versions

# The latest DocumentVersion (highest version_number).
article.current_version   # => Docsmith::DocumentVersion

# A specific DocumentVersion by version_number (1-indexed). Returns nil if not found.
article.version(3)        # => Docsmith::DocumentVersion | nil

# Creates a new version whose content is copied from version N. Never mutates history.
# Returns the new DocumentVersion.
article.restore_version!(3, author: user)

# Tags a specific version by version_number. Raises if the name is already taken
# on this document (unique per document, not just per version).
article.tag_version!(3, name: "v1.0-release", author: user)

# Returns the DocumentVersion that carries this tag, or nil.
article.tagged_version("v1.0-release")   # => Docsmith::DocumentVersion | nil

# Returns array of tag name strings for version N.
article.version_tags(3)   # => ["v1.0-release", "draft"]
```

### `max_versions` pruning

When `max_versions` is configured and a new version would exceed the limit:
1. Delete the oldest version that has **no tags**. Tagged versions are exempt (they are pinned).
2. If all versions are tagged and the limit is still exceeded, raise `Docsmith::MaxVersionsExceeded`.
3. When `max_versions: nil` (gem default), no pruning occurs — unlimited history.

### Content validation

Before any snapshot, Docsmith reads the content via:
- `content_extractor.call(record)` if a proc is configured (per-class or global), otherwise
- `record.send(content_field)`

If the result is not a `String`, raises `Docsmith::InvalidContentField` with a message that
points the user to the `content_extractor` option.

---

## Section 3: Internal Architecture

### `Docsmith::VersionManager`

All mixin methods delegate here. The mixin is a thin API surface; `VersionManager` owns the logic.
Always receives a `Docsmith::Document` instance — the mixin resolves the shadow document first.

```ruby
Docsmith::VersionManager.save!(document, author:, summary: nil)
# Reads document.content, compares to latest version content using simple string == (v1).
# Returns nil if identical (no-op).
# Inserts DocumentVersion, increments versions_count, updates last_versioned_at.
# Prunes oldest untagged version if max_versions exceeded (raises if all tagged).
# Fires :version_created event.

Docsmith::VersionManager.restore!(document, version:, author:)
# Finds DocumentVersion by version_number.
# Copies its content into document.content, then calls save!.
# Fires :version_restored event.

Docsmith::VersionManager.tag!(document, version:, name:, author:)
# Finds DocumentVersion by version_number.
# Creates VersionTag. Raises if name already taken on this document.
# Fires :version_tagged event.
```

### `Docsmith::AutoSave`

Extracted into its own class for independent testability. The debounce window calculation is
exposed publicly so specs can assert on it directly without mocking time.

```ruby
Docsmith::AutoSave.call(document, author:)
# Checks document.last_versioned_at against configured debounce.
# Returns nil if within debounce window.
# Otherwise delegates to VersionManager.save!

Docsmith::AutoSave.within_debounce?(document)
# Returns true if the debounce window has not elapsed. Public for testability.
```

### `Docsmith::Configuration`

```ruby
Docsmith::Configuration::DEFAULTS = {
  content_field:     :body,
  content_type:      :markdown,
  auto_save:         true,
  debounce:          30,          # integer seconds (not ActiveSupport::Duration — no AS dep here)
  max_versions:      nil,
  content_extractor: nil
}.freeze
```

`.resolve(class_config, global_config)` merges per-class over global over defaults at read time.
No mutation of either config object — returns a plain hash.

**Debounce normalization:** `debounce` accepts both `Integer` (seconds) and
`ActiveSupport::Duration` (e.g., `60.seconds`). The config system normalizes any Duration to
an integer via `.to_i` at read time, so internal comparisons always use plain integers.

### `Docsmith::Events`

Every action fires **both** the hook registry and `ActiveSupport::Notifications`. Neither is optional.

**Components:**
- `Docsmith::Events::HookRegistry` — stores procs per event name, calls them synchronously.
- `Docsmith::Events::Notifier` — wraps `ActiveSupport::Notifications.instrument`.
- `Docsmith::Events::Event` — struct carrying the payload fields below.

**Payload fields by event:**

| Event              | `record` | `document` | `version` | `author` | extras          |
|--------------------|----------|------------|-----------|----------|-----------------|
| `version_created`  | ✓        | ✓          | ✓         | ✓        | —               |
| `version_restored` | ✓        | ✓          | ✓         | ✓        | `from_version`  |
| `version_tagged`   | ✓        | ✓          | ✓         | ✓        | `tag_name`      |

- `event.record` — the originating AR object (`Article` instance when using mixin,
  `Docsmith::Document` when using standalone API).
- `event.document` — always the `Docsmith::Document` shadow record.

AS::Notifications instrument names: `"version_created.docsmith"`, `"version_restored.docsmith"`,
`"version_tagged.docsmith"`.

---

## Section 4: Generator & Test Setup

### `rails generate docsmith:install`

Produces:

**`db/migrate/TIMESTAMP_create_docsmith_tables.rb`**
Creates all three tables in a single migration. Safe on PostgreSQL, MySQL, and SQLite.
Column order matches the schema in Section 1 exactly.

**`config/initializers/docsmith.rb`**

```ruby
Docsmith.configure do |config|
  # config.default_content_field    = :body
  # config.default_content_type     = :markdown    # :html, :markdown, :json
  # config.auto_save                = true
  # config.default_debounce         = 30           # integer seconds
  # config.max_versions             = nil          # nil = unlimited
  # config.content_extractor        = nil          # ->(record) { record.body.to_html }
  # config.table_prefix             = "docsmith"
  # config.diff_context_lines       = 3            # used in Phase 2
end
```

### Test setup (`spec/support/`)

**`spec/support/schema.rb`**
In-memory SQLite schema that mirrors the migration exactly. Single source of truth for the
test DB. If the migration changes, this file changes too.

**`spec/support/models.rb`**
Minimal AR models for specs:

```ruby
class Article < ActiveRecord::Base
  include Docsmith::Versionable
  docsmith_config { content_field :body; content_type :markdown }
end

class Post < ActiveRecord::Base
  include Docsmith::Versionable
  # uses all gem defaults
end
```

**`spec_helper.rb`** additions:
- Requires `active_record`, `sqlite3`, `factory_bot`.
- Establishes in-memory SQLite connection before suite.
- Loads `spec/support/schema.rb` then `spec/support/models.rb`.
- Wraps each example in a transaction (rollback after each test — no truncation needed).
- Includes `FactoryBot::Syntax::Methods`.

---

## Decisions Log

| # | Question | Decision |
|---|----------|----------|
| 1 | Mixin + docsmith_documents relationship | A — shadow document with `subject_type/subject_id` on `docsmith_documents`; `from_record` does find-or-create |
| 2 | `content` column on `docsmith_documents` | B — add `content :text`; live content field; `save_version!` snapshots from it |
| 3 | `current_version` naming collision | A — rename column to `versions_count`; `current_version` method returns `DocumentVersion` |
| 4 | AR model class name | C — `Docsmith::DocumentVersion`; avoids collision with `version.rb` gem constant file |
| 5 | Debounce storage | A — `last_versioned_at :datetime` on `docsmith_documents` |
| 6 | `save_version!` on identical content | C — returns `nil` (no-op); returns `DocumentVersion` on save |
| 7 | `max_versions` pruning | C — prune oldest untagged; tagged versions exempt; raise `MaxVersionsExceeded` if all tagged; `nil` default = unlimited |
| 8 | Event `document` payload | C — `event.record` (originating AR object) + `event.document` (shadow `Docsmith::Document`) |
| 9 | Non-string content fields | B + C — raise `Docsmith::InvalidContentField` by default; `content_extractor` proc available as opt-in (per-class or global) |
| 10 | `auto_save_version!` no-op return | B — `nil` for both skip reasons (debounced or unchanged) |
