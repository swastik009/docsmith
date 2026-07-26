# Changelog

All notable changes to this project will be documented here.

## [Unreleased]

## [0.2.0] - 2026-07-26

### Added

- **`Diff::Result#as_json`** — the canonical diff payload, and now the single
  source of truth for it. `to_json` delegates to it.
- **`Diff::Result#modifications` and `#stats`** — explicit change counts.
- **`Rendering::JsonRenderer#to_h`** — the canonical content envelope; `#render`
  is `to_h(...).to_json`.
- **`DocumentVersion#export(**options)`** — the envelope as a Hash, for embedding
  a version in a larger API response without a JSON round-trip. `as_json` is
  deliberately NOT overridden on the model, so `render json: @version` still
  returns plain ActiveRecord attributes.
- **`schema_version`** on both envelopes, sourced from
  `Docsmith::JSON_SCHEMA_VERSION`. Clients should branch on this rather than on
  the gem version.
- **`include_parsed: true`** on the content export, adding a `data` key with the
  parsed document for `content_type: "json"`. No-op for other content types.
- `Docsmith::InvalidJsonContent`, raised when `include_parsed` is set and the
  content does not parse.
- `config.html_sanitizer` — controls how `render(:html)` treats stored html
  content. Accepts `nil` (default: escape), any object responding to `#call`, or
  `:unsafe_raw`. See the Security note below.
- `Docsmith::InvalidHtmlSanitizer` error, raised when `html_sanitizer` is set to
  something that is neither callable, `:unsafe_raw`, nor `nil`.

### Changed

- **Both JSON exports are a new, single, documented shape.** This is a breaking
  wire-format change with no compatibility flag.

  **`Diff::Result` — nesting no longer produces a different payload.** `as_json`
  was undefined, so nesting fell through to `Object#as_json` (`instance_values`):

  ```jsonc
  // BEFORE — result.to_json (documented)
  { "content_type": "markdown", "from_version": 1, "to_version": 3,
    "stats": { "additions": 2, "deletions": 0 },
    "changes": [ { "type": "modification", "position": { "line": 4 }, … } ] }

  // BEFORE — { diff: result }.to_json, i.e. `render json: { diff: result }`
  // no "stats" at all, and "line" instead of "position"
  { "diff": { "content_type": "markdown", "from_version": 1, "to_version": 3,
              "changes": [ { "type": "modification", "line": 4, … } ] } }

  // AFTER — identical either way, plus schema_version and full stats
  { "schema_version": 1, "content_type": "markdown",
    "from_version": 1, "to_version": 3,
    "stats": { "additions": 2, "deletions": 0, "modifications": 1, "total": 3 },
    "changes": [ { "type": "modification", "position": { "line": 4 }, … } ] }
  ```

  **`render(:json)` — one envelope instead of two schemas.** It previously returned
  the bare pretty-printed document for `content_type: "json"` and an envelope for
  everything else, so no client could parse it generically:

  ```jsonc
  // BEFORE — content_type "json": no envelope, reformatted
  { "title": "Doc", "tags": [ "a" ] }

  // BEFORE — any other content_type: envelope, two keys
  { "content_type": "markdown", "content": "# Hello" }

  // AFTER — one shape for every content_type
  { "schema_version": 1, "document_id": 7, "version_number": 2,
    "content_type": "markdown", "content": "# Hello\n\nSecond draft.",
    "change_summary": "Second draft",
    "author": { "type": "User", "id": 1 },
    "metadata": {}, "created_at": "2026-03-01T14:22:00.000Z" }
  ```

  Also note: `content` is now **always the exact stored string**, byte for byte.
  JSON documents are no longer pretty-printed on export, so an export matches what
  was versioned. And `USAGE.md` previously documented a `"version"` key that the
  implementation never emitted; the envelope now carries `version_number`.

- **`changes` is redesigned: grouped edits with real positions.** The old array had
  no usable semantics. Each *token* was its own entry, so a one-line heading
  rewrite produced seven of them. The `position.line` they carried was a **token
  index, not a line number** — it could exceed the document's line count — and it
  silently mixed coordinate systems, using an old-document index for deletions and
  a new-document index for additions, so the values were not even comparable to
  each other.

  ```jsonc
  // BEFORE — "my document" -> "<h1>this is a new heading</h1>"
  // in a 3-line document. Seven entries; "line" reaches 7.
  "changes": [
    { "type": "modification", "position": { "line": 1 },
      "old_content": "my", "new_content": "<h1>" },
    { "type": "modification", "position": { "line": 2 },
      "old_content": "document", "new_content": "this" },
    { "type": "addition", "position": { "line": 3 }, "content": "is" },
    { "type": "addition", "position": { "line": 4 }, "content": "a" },
    { "type": "addition", "position": { "line": 5 }, "content": "new" },
    { "type": "addition", "position": { "line": 6 }, "content": "heading" },
    { "type": "addition", "position": { "line": 7 }, "content": "</h1>" }
  ]

  // AFTER — one entry, real offsets and line numbers on both sides
  "changes": [
    { "type": "replace",
      "old": { "start": 0, "end": 11, "line": 1, "column": 1,
               "text": "my document" },
      "new": { "start": 0, "end": 30, "line": 1, "column": 1,
               "text": "<h1>this is a new heading</h1>" } }
  ]
  ```

  - A contiguous run of edits collapses into **one** entry. A pure-insert run is
    `insert`, pure-delete is `delete`, mixed is `replace`.
  - **Both sides are always present**, so every entry has identical keys. A pure
    insertion carries a zero-width `old` span marking the insertion point, which
    also makes the payload applyable as a patch.
  - `start`/`end` are character offsets (end exclusive); `line`/`column` are real
    1-indexed positions. `content[start...end] == text`, so clients can slice
    their own context.
  - `old` and `new` never share a coordinate space.
  - `Result#changes` returns the same structure symbol-keyed, so Ruby and JSON
    agree on what a change is. `Renderers::Base#render_html` consumes it.

- **Edit types and `stats` keys use standard diff vocabulary.** Types are now
  `insert` / `delete` / `replace` (was `addition` / `deletion` / `modification`),
  and `stats` is `insertions` / `deletions` / `replacements` / `total`. Ruby readers
  match: `#insertions`, `#deletions`, `#replacements`. Previously a diff whose every
  line changed reported `additions: 0, deletions: 0` alongside a non-empty
  `changes` array; a replacement is now counted once, and for git-style totals you
  add `replacements` to either side.

- The format-aware parsers were reduced to their tokenizer. `Parsers::Markdown` and
  `Parsers::Html` had near-identical copies of `compute`; grouping, offsets, and
  rendering now live once in `Renderers::Base` and subclasses override `tokenize`
  only. A custom renderer registered via `Renderers::Registry` should do the same.

- **`Comments::Comment#anchor_data` takes a Hash.** The hand-rolled accessor pair
  that existed only to paper over the `:text` column is gone. Passing a
  pre-serialized JSON String now stores it as a JSON string literal and reads
  back as a String, where the old `:text` column parsed it into a Hash. Callers
  doing `anchor_data: data.to_json` should pass `anchor_data: data`.

### Security

- **Fixed stored XSS in `version.render(:html)` for `content_type: "html"`.** The
  renderer returned stored content verbatim, so any HTML that originated from a
  user executed in the browser. html content is now escaped by default and
  rendered only through an explicitly configured sanitizer.

  Docsmith deliberately ships no sanitizer — a safe one requires a real HTML
  parser, and adding Nokogiri would break the zero-system-dependency guarantee.

  **This is a breaking change for anyone rendering html documents.** To restore
  rendering, pick one:

  ```ruby
  # Recommended — Rails already bundles this via ActionView, so no new gem:
  config.html_sanitizer = ->(html) { Rails::HTML5::SafeListSanitizer.new.sanitize(html) }

  # Verbatim passthrough, i.e. the old behavior. Only for HTML you fully trust:
  config.html_sanitizer = :unsafe_raw
  ```

  A non-callable, non-`:unsafe_raw` value raises `Docsmith::InvalidHtmlSanitizer`
  instead of degrading to raw output. Markdown and JSON rendering are unaffected,
  and diff output was already escaped for every content type.

### Fixed

- **`rails generate docsmith:install` never worked.** The generator's action method
  was named `create_migration`, which shadows `Rails::Generators::Migration`'s own
  `create_migration(destination, data, config)` — the method `migration_template`
  calls internally. Running the generator died with `ArgumentError: wrong number of
  arguments (given 3, expected 0)` before writing a single file, so the documented
  first step of installing the gem failed outright in 0.1.0. Renamed to
  `create_migration_file`.

  This went unnoticed because the generator had no test coverage: `railties`
  provides `rails/generators` and was not a development dependency, so the spec
  suite could not load the generator at all. `railties` is now a **development**
  dependency — deliberately not a runtime one, since docsmith targets plain
  ActiveRecord and nothing in `lib/docsmith.rb` loads Rails. The generator now has
  specs that run it against a temp directory and execute the migration it produces.
- JSON payload columns (`metadata`, `anchor_data`) are now `:json` rather than
  `:text` in the gem's own schemas. They previously read back as a `Hash` on
  PostgreSQL and as the literal String `"{}"` on SQLite and MySQL, so models saw
  a different type in tests than in production.
- `rails generate docsmith:install` no longer emits a PostgreSQL-only migration.
  It picks `jsonb` for PostgreSQL-derived adapters and `json` elsewhere, so the
  generated migration runs on MySQL and SQLite instead of failing on `t.jsonb`.
- `Comments::Anchor.migrate` no longer raises `TypeError` out of the middle of a
  comment migration when an anchor is missing its `anchored_text` or offsets.
  Such anchors are now reported as `orphaned`.
- `Comments::Comment#anchor_data` no longer raises an unrescued
  `JSON::ParserError` from a plain attribute reader on malformed stored data.

### Demo

- Added an **HTML & Sanitizer** section (`/pages`) built on a `content_type :html`
  model, showing `render(:html)` output under each `html_sanitizer` mode against
  content containing a `<script>` tag. Seeded automatically.
- **Fixed stored XSS in the demo's own views.** Sinatra's stock ERB does not
  escape `<%= %>`, so an article title, comment body, or tag name containing a
  `<script>` tag executed in the browser. The route classes now set
  `erb, escape_html: true`, and the two places that intentionally emit HTML
  (`layout.erb`'s `yield`, `diff.erb`'s `to_html`) use `<%== %>`.
- `demo/db/setup.rb` migrates pre-existing demo databases from the old `:text`
  columns to `:json` via `change_column`, preserving all rows. The `create_table`
  calls are guarded by `table_exists?`, so without this an existing demo DB would
  have silently kept its old column types.

### Upgrading

- **No migration is required for existing installs.** The column-type fix affects
  the schemas Docsmith ships for its own tests and demo; installs generated
  before this release already have `jsonb` columns, which behave identically.
  The generator change only matters for new installs on MySQL and SQLite, where
  the old `t.jsonb` migration could not run at all.
- If you render `content_type: "html"` documents, set `config.html_sanitizer`
  before upgrading, or that content will render escaped.
- If you pass `anchor_data:` a pre-serialized JSON String anywhere, change it to
  pass the Hash directly.
- **Update any consumer of the two JSON exports.** Both shapes changed and there is
  no compatibility flag. Branch on `schema_version` going forward.
  - If you parsed `render(:json)` for a `content_type: "json"` document, the
    document is no longer the payload root — read `content` (a string) or pass
    `include_parsed: true` and read `data`.
  - If you nested a `Diff::Result` and worked around the missing `stats` by calling
    `JSON.parse(result.to_json)` first, you can now pass the result directly.
  - If you read `additions`/`deletions` as an overall change count, read
    `stats["total"]`, or add `replacements` to either side.
  - Rename `result.additions` to `result.insertions` and `result.modifications` to
    `result.replacements`. `result.deletions` keeps its name.
  - If you walked `result.changes`, it is now grouped edits with `old`/`new` spans
    rather than a flat token list. Anything reading `c[:line]` or `c[:content]`
    needs updating — and note that `c[:line]` was never a line number.
  - If you subclassed a parser or registered a custom diff renderer, override
    `#tokenize` (returning `[text, start_offset]` pairs) instead of `#compute`.
- **`config.diff_context_lines` is removed.** It was declared and documented but
  read by nothing, so it never had any effect. With real `start`/`end` offsets on
  both sides of every edit, a client can slice whatever context it needs from the
  document text.

## [0.1.0] - 2026-04-12

First public release.

### Added

- `Docsmith::Versionable` mixin — include in any ActiveRecord model to enable versioning
- Snapshot-based versioning: full content snapshots for HTML, Markdown, and JSON with instant rollback to any version
- Format-aware diff engine: word-level diffs for Markdown, tag-atomic diffs for HTML
- Inline and document-level comments with threading, resolution, and version migration
- Debounced auto-save with configurable threshold per class
- Per-class and global configuration via `docsmith_config` block
- Lifecycle events: `version_created`, `version_restored`, `version_tagged`
- Standalone `Docsmith::Document` service API — works without a model mixin
- `rails generate docsmith:install` generator with migration
- Zero system dependencies — pure Ruby on top of ActiveRecord and diff-lcs
