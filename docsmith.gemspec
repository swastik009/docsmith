# frozen_string_literal: true

require_relative 'lib/docsmith/version'

Gem::Specification.new do |spec|
  spec.name = 'docsmith'
  spec.version = Docsmith::VERSION
  spec.authors = ['swastik009']
  spec.email = ['swastik.thapaliya@gmail.com']

  spec.summary = 'Plug-and-play document version manager for Rails'
  spec.description = <<~DESC
    Docsmith adds snapshot-based versioning to any ActiveRecord model with zero system dependencies.

    • Full content snapshots (HTML, Markdown, JSON) for instant rollbacks
    • Format-aware diff engine: word-level diffs for Markdown, tag-atomic diffs for HTML
    • Document-level and range-anchored comments with threading and version migration
    • Per-class configuration, debounced auto-save, lifecycle events, and a clean API

    Perfect for wikis, CMS pages, API specs, legal documents, or any content that needs
    an audit trail and inline collaboration.
  DESC
  spec.homepage = 'https://www.altcipher.com'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/swastik009/docsmith"
  spec.metadata["changelog_uri"]   = "https://github.com/swastik009/docsmith/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency "activerecord",  "~> 7.0"
  spec.add_dependency "activesupport", "~> 7.0"
  spec.add_dependency "diff-lcs",      "~> 1.5"

  spec.add_development_dependency "rspec",       "~> 3.12"
  spec.add_development_dependency "sqlite3",     "~> 1.4"
  spec.add_development_dependency "factory_bot", "~> 6.0"
  spec.add_development_dependency "rubocop",     "~> 1.50"
end
