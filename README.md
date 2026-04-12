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

## How this was built

Honest note: this gem was built over two weekends using [Claude Code](https://claude.ai/code) with the superpowers plugin. Not vibe-coding — the planning, architecture decisions, and implementation were all deliberate. If you're curious how it came together, the planning docs and implementation notes are in [docs/superpowers](docs/superpowers).

Early designs got ambitious fast — branching, merging, conflict resolution. Turns out that's a lot of machinery for what is ultimately a document version manager. I stripped it back to what actually matters: snapshots, diffs, and comments. You can see all the planning in [docs/superpowers](docs/superpowers).

## License

MIT — see [LICENSE.txt](LICENSE.txt).
