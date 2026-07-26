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

### Rendering stored HTML safely — `html_sanitizer`

Stored HTML is untrusted input. If any of your `content_type: :html` documents
originated from a user, rendering them verbatim is **stored XSS**. Docsmith ships
no sanitizer of its own: sanitizing safely requires a real HTML parser, and
vendoring one would break the gem's zero-system-dependency guarantee.

So `render(:html)` escapes html content by default, and you opt into rendering it:

```ruby
Docsmith.configure do |config|
  # Default (html_sanitizer unset) — content is escaped inside
  # <pre class="docsmith-html">. Safe, and visible enough that you notice it.

  # Recommended. Rails already bundles this via ActionView, so no new gem:
  config.html_sanitizer = ->(html) { Rails::HTML5::SafeListSanitizer.new.sanitize(html) }

  # Verbatim passthrough. Only for HTML you generate yourself and fully trust:
  config.html_sanitizer = :unsafe_raw
end
```

Anything else — a String, a non-callable object — raises
`Docsmith::InvalidHtmlSanitizer` rather than quietly falling back to raw output.

This affects **only** `render(:html)` for `content_type: "html"`. Markdown and JSON
were always escaped, and diff output (`Diff::Result#to_html`) escapes every change
field regardless of content type.

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
article.version(2).render(:json)    # => JSON envelope string, see below
article.version(2).export           # => the same envelope as a Hash
```

### JSON export envelope

`render(:json)` returns a **single shape for every `content_type`**, so one parser
handles all of them:

```ruby
JSON.parse(article.version(2).render(:json))
# => {
#   "schema_version" => 1,
#   "document_id"    => 7,
#   "version_number" => 2,
#   "content_type"   => "markdown",
#   "content"        => "# Hello\n\nSecond draft.",
#   "change_summary" => "Second draft",
#   "author"         => { "type" => "User", "id" => 1 },
#   "metadata"       => {},
#   "created_at"     => "2026-03-01T14:22:00.000Z"
# }
```

- **`content` is always the exact stored string**, byte for byte, for every content
  type. Docsmith never reformats it: this is a versioning gem, and an export that
  re-serialized the snapshot would not match what was versioned.
- **`author` is type and id only**, or `null`. The gem never serializes your author
  record — it cannot know which of its fields are personal data.
- **`schema_version`** identifies the wire format. Branch on it rather than on the
  gem version. It changes only when the payload shape changes.

To embed a version in a larger response without a JSON round-trip, use `#export`,
which returns the same Hash:

```ruby
render json: { article: article.as_json, version: article.version(2).export }
```

`DocumentVersion#as_json` is deliberately **not** overridden — `render json: @version`
still returns plain ActiveRecord attributes.

### Parsed JSON documents — `include_parsed`

For `content_type: "json"` documents you can request the parsed document alongside
the raw string:

```ruby
version.export(include_parsed: true)
# => { ..., "content" => '{"title":"Doc"}', "data" => { "title" => "Doc" } }
```

`content` still holds the exact bytes; `data` is the parsed form. On a non-json
document the option is a no-op. If the content does not parse, this raises
`Docsmith::InvalidJsonContent` — the **default export path never parses**, so it
cannot fail on malformed content.

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

result.insertions    # => count of PURE insertions
result.deletions     # => count of PURE deletions
result.replacements  # => count of spans replaced
result.stats         # => all of the above plus "total"
result.changes       # => grouped edits, see below
result.to_html       # => HTML string with <ins>/<del> markup
result.to_json       # => JSON string, see below
result.as_json       # => the same payload as a Hash
```

**`insertions` and `deletions` count only pure inserts and removals.** A changed
span counts once as a `replacement`, not as one of each. For git-style totals, add
`replacements` to either side:

```ruby
git_style_insertions = result.insertions + result.replacements
```

### What a change looks like

Each entry in `changes` is a **contiguous run of edits collapsed into one**, with
genuine character offsets and line numbers on **both** sides:

```ruby
# v1: "my document\n\nsecond para"
# v2: "<h1>this is a new heading</h1>\n\nsecond para"
result.changes
# => [
#   { type: :replace,
#     old: { start: 0, end: 11, line: 1, column: 1, text: "my document" },
#     new: { start: 0, end: 30, line: 1, column: 1,
#            text: "<h1>this is a new heading</h1>" } }
# ]
```

- **`type`** is `:insert`, `:delete`, or `:replace`.
- **Both sides are always present.** A pure insertion carries a zero-width `old`
  span (`start == end`, empty text) marking *where* it was inserted; a pure deletion
  carries a zero-width `new` span. Every entry therefore has identical keys, so you
  never branch on type to know which fields exist.
- **`line` and `column` are real 1-indexed positions** in that document, and
  `start`/`end` are character offsets (end exclusive). `content[start...end]` is
  exactly `text`, so you can slice as much surrounding context as you want.
- **`old` and `new` never share a coordinate space** — `old` offsets index the older
  document, `new` offsets the newer one.

> **Changed in 0.2.0.** Previously each *token* was its own entry, so a one-line
> heading rewrite produced seven of them. Worse, the `position.line` they carried
> was a **token index, not a line number** — it could exceed the document's line
> count — and it silently mixed coordinate systems, using an old-document index for
> deletions and a new-document index for additions.

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
# => [{ type: :replace,
#       old: { start: 10, end: 15, line: 1, column: 11, text: "brown" },
#       new: { start: 10, end: 13, line: 1, column: 11, text: "red" } }]
result.stats
# => { "insertions" => 0, "deletions" => 0, "replacements" => 1, "total" => 1 }
```

Words between two edits keep them separate — `"the quick brown fox"` to
`"the slow brown wolf"` yields **two** replaces, because `brown` is unchanged.

**HTML example:**

```ruby
# v1 content: "<p>Hello world</p>"
# v2 content: "<p>Hello world</p><p>New paragraph</p>"
# The four added tokens ("<p>", "New", "paragraph", "</p>") are one contiguous
# run, so they collapse into a single insert.
result = article.diff_between(1, 2)
result.insertions          # => 1
result.changes.first[:new][:text]
# => "<p>New paragraph</p>"
```

Note the tokenizer discards the whitespace *between* tokens, but an edit's `text`
is sliced from the source between its offsets — so spaces and newlines inside a
run are preserved verbatim.

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
#   "schema_version" => 1,
#   "content_type"   => "markdown",
#   "from_version"   => 1,
#   "to_version"     => 3,
#   "stats"          => { "insertions" => 1, "deletions" => 0,
#                         "replacements" => 1, "total" => 2 },
#   "changes"        => [
#     { "type" => "replace",
#       "old" => { "start" => 0,  "end" => 11, "line" => 1, "column" => 1,
#                  "text" => "my document" },
#       "new" => { "start" => 0,  "end" => 30, "line" => 1, "column" => 1,
#                  "text" => "<h1>this is a new heading</h1>" } },
#     { "type" => "insert",
#       "old" => { "start" => 24, "end" => 24, "line" => 3, "column" => 13,
#                  "text" => "" },
#       "new" => { "start" => 43, "end" => 52, "line" => 3, "column" => 13,
#                  "text" => " appended" } }
#   ]
# }
```

### Nesting a diff in a larger response

`Diff::Result` implements `as_json`, so it serializes identically whether it is
encoded on its own or nested anywhere inside another structure:

```ruby
render json: { diff: result }             # correct payload under "diff"
render json: { diffs: [result, other] }   # correct payload in each element
JSON.generate(result)                     # same as result.to_json
```

> **Fixed in 0.2.0.** `as_json` was previously undefined, so nesting fell through
> to `Object#as_json` and produced a **different** payload from `to_json` — with no
> `stats` key at all, and the raw internal change hashes in place of the documented
> ones. If you worked around this by calling `JSON.parse(result.to_json)` before
> nesting, you can now pass the result directly.

`result.changes` is the same structure symbol-keyed, so there is exactly one model
of what a change is:

```ruby
{ type: :replace,
  old: { start: 0, end: 11, line: 1, column: 1, text: "my document" },
  new: { start: 0, end: 30, line: 1, column: 1, text: "<h1>..." } }
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
result.insertions  # => number of pure insertions
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

**Error classes:**

| Class | Raised when |
|-------|-------------|
| `Docsmith::InvalidContentField` | `content_field` returns a non-String |
| `Docsmith::VersionNotFound` | Requested version number does not exist |
| `Docsmith::TagAlreadyExists` | Tag name already used on this document |
| `Docsmith::MaxVersionsExceeded` | All versions are tagged and pruning is blocked |
