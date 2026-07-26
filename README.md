# Docsmith

[![Gem Version](https://badge.fury.io/rb/docsmith.svg)](https://rubygems.org/gems/docsmith)

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
result.stats       # => {"insertions"=>1, "deletions"=>0, "replacements"=>1, "total"=>2}
result.changes     # grouped edits with character offsets and line numbers
result.to_html     # <ins>/<del> markup
result.as_json     # canonical JSON payload, identical when nested
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

## How this was built

Honest note: this gem was built over two weekends using [Claude Code](https://claude.ai/code) with the superpowers plugin. Not vibe-coding — the planning, architecture decisions, and implementation were all deliberate. If you're curious how it came together, the planning docs and implementation notes are in [docs/superpowers](docs/superpowers).

Early designs got ambitious fast — branching, merging, conflict resolution. Turns out that's a lot of machinery for what is ultimately a document version manager. I stripped it back to what actually matters: snapshots, diffs, and comments. You can see all the planning in [docs/superpowers](docs/superpowers).

## License

MIT — see [LICENSE.txt](LICENSE.txt).
