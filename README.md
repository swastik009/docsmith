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
