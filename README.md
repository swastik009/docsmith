# Docsmith

[![Gem Version](https://badge.fury.io/rb/docsmith.svg)](https://rubygems.org/gems/docsmith)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.1-CC342D.svg)](https://www.ruby-lang.org)
[![Rails](https://img.shields.io/badge/activerecord-%7E%3E%207.0-CC0000.svg)](https://rubyonrails.org)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)

Docsmith adds snapshot-based versioning, format-aware diffs, and inline comments to any
ActiveRecord model — with zero system dependencies.

Requires **Ruby >= 3.1** and **ActiveRecord ~> 7.0**. Works with or without Rails: the
only runtime dependencies are `activerecord`, `activesupport`, and `diff-lcs`.

> **Upgrading from 0.1.x?** 0.2.0 contains breaking changes to both JSON exports and to
> HTML rendering. See the [Upgrading notes](CHANGELOG.md#upgrading) before you bump.

## Features

- **Full content snapshots** for HTML, Markdown, and JSON — instant rollback to any version
- **Format-aware diffs** — word-level for Markdown, tag-atomic for HTML, line-level for JSON
- **Grouped diff edits** — contiguous changes collapse into one entry carrying real character
  offsets and line numbers on both the old and new side
- **One JSON envelope** for every content type, with a `schema_version` clients can branch on,
  and byte-exact content so an export matches what was versioned
- **Safe HTML rendering** — stored HTML is escaped unless you configure a sanitizer, so
  user-supplied content is not a stored-XSS vector
- **Inline and document-level comments** with threading, resolution, and version migration
- **Debounced auto-save** with per-class and global configuration
- **Lifecycle events** — hook into version_created, version_restored, version_tagged
- **Clean service API** — works standalone without any model mixin

## Quick Start

```ruby
# Gemfile
gem "docsmith", "~> 0.2"
```

```bash
bundle install
rails generate docsmith:install
rails db:migrate
```

```ruby
class Article < ApplicationRecord
  include Docsmith::Versionable
  docsmith_config { content_field :body; content_type :markdown }
end

article = Article.find(1)
article.update!(body: "New draft")
article.save_version!(author: current_user, summary: "First draft")
```

Diff any two versions:

```ruby
result = article.diff_from(1)

result.stats       # => {"insertions"=>1, "deletions"=>0, "replacements"=>1, "total"=>2}
result.to_html     # <ins>/<del> markup
result.as_json     # canonical payload — identical standalone or nested

result.changes
# => [{ type: :replace,
#       old: { start: 0, end: 11, line: 1, column: 1, text: "my document" },
#       new: { start: 0, end: 22, line: 1, column: 1, text: "<h1>a new heading</h1>" } }]
```

Export a version as JSON:

```ruby
article.version(2).export
# => { "schema_version" => 1, "document_id" => 7, "version_number" => 2,
#      "content_type" => "markdown", "content" => "# Hello\n\nSecond draft.",
#      "change_summary" => "Second draft", "author" => { "type" => "User", "id" => 1 },
#      "metadata" => {}, "created_at" => "2026-03-01T14:22:00.000Z" }
```

Rendering `content_type: :html` documents requires a sanitizer, because stored HTML is
untrusted — see [Rendering stored HTML safely](USAGE.md#5-global-configuration):

```ruby
Docsmith.configure do |config|
  # Rails already bundles this via ActionView, so no extra gem:
  config.html_sanitizer = ->(html) { Rails::HTML5::SafeListSanitizer.new.sanitize(html) }
end
```

## Example App

A self-contained Sinatra demo is in [`demo/`](demo/). It shows versioning, diffs, and comments working end-to-end — no Rails required.

```bash
cd demo
bundle install
bundle exec rackup
# open http://localhost:9292
```

The demo loads the gem from the parent directory as a path dependency, so the
`bundle exec` prefix is required. `bundle exec ruby app.rb` also works and
serves on port 4567.

Two sections: **Articles** covers markdown versioning, diffs, tags, and comments.
**HTML & Sanitizer** uses `content_type :html` to show what `render(:html)` returns
under each `config.html_sanitizer` mode, side by side, against content containing a
`<script>` tag.

The demo installs `rails-html-sanitizer` to demonstrate the recommended sanitizer
setup, and `erubi` to turn on ERB escaping. Neither is a Docsmith dependency — the
gem itself still has none beyond ActiveRecord, ActiveSupport, and diff-lcs.

## Documentation

See **[USAGE.md](USAGE.md)** for full documentation including:

- Installation and migration
- Per-class and global configuration
- Saving, querying, and restoring versions
- Version tagging
- Format-aware diffs, the grouped edit structure, and nesting a diff in an API response
- The JSON export envelope, `#export`, and `include_parsed`
- Rendering stored HTML safely with `config.html_sanitizer`
- Inline and document-level comments
- Events and hooks
- Standalone Document API
- Configuration reference

See **[CHANGELOG.md](CHANGELOG.md)** for release notes and upgrade instructions.

## Development

```bash
bin/setup
bundle exec rspec    # run tests
bin/console          # interactive console
```

## How this was built

Honest note: this gem was built over two weekends using [Claude Code](https://claude.ai/code) with the superpowers plugin. Not vibe-coding — the planning, architecture decisions, and implementation were all deliberate. If you're curious how it came together, the planning docs and implementation notes are in [docs/superpowers](docs/superpowers).

Early designs got ambitious fast — branching, merging, conflict resolution. Turns out that's a lot of machinery for what is ultimately a document version manager. I stripped it back to what actually matters: snapshots, diffs, and comments. You can see all the planning in [docs/superpowers](docs/superpowers).

## License

MIT — see [LICENSE.txt](LICENSE.txt).
