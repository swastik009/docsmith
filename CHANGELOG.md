# Changelog

All notable changes to this project will be documented here.

## [Unreleased]

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
