# Docsmith — Full Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Docsmith gem in four phases — core versioning, diff/rendering, comments, and branching — all via ActiveRecord with zero system dependencies.

**Architecture:** Full content snapshots stored in `docsmith_versions` (never deltas). Diffs computed on read via pure-Ruby `diff-lcs`. A `Docsmith::Document` shadow record is auto-created for any AR model that `include Docsmith::Versionable`. All operations go through service objects (`VersionManager`, `AutoSave`) that the mixin delegates to.

**Tech Stack:** Ruby ≥ 3.1, Rails ≥ 7.0, ActiveRecord, ActiveSupport::Notifications, diff-lcs (~> 1.5), RSpec, FactoryBot, SQLite (test only).

**Locked-in decisions (enforce throughout):**
- `frozen_string_literal: true` in every Ruby file
- `Docsmith::DocumentVersion` class — table `docsmith_versions` via `self.table_name`
- `versions_count :integer` on `docsmith_documents` (NOT `current_version`)
- `last_versioned_at :datetime` on `docsmith_documents` for debounce
- `content :text` column on `docsmith_documents` (live content field)
- `subject_type / subject_id` polymorphic on `docsmith_documents`
- `document_id` on `docsmith_version_tags`; unique index `[document_id, name]`
- `event.record` (originating AR object) + `event.document` (shadow Document) on ALL events
- Config precedence: per-class `docsmith_config` > global `Docsmith.configure` > gem defaults
- `save_version!` returns `nil` on unchanged content
- `auto_save_version!` returns `nil` for both skip reasons (debounced OR unchanged)
- `max_versions: nil` = unlimited; prune oldest **untagged** version when limit set
- `content_extractor` proc opt-in; raise `InvalidContentField` for non-String content
- Every public method has RDoc (`# @param`, `# @return`)
- All AR queries are scope-based — no raw SQL strings

---

## File Map — Phase 1

| File | Action | Responsibility |
|---|---|---|
| `docsmith.gemspec` | Modify | Add runtime + dev dependencies |
| `Gemfile` | Modify | Remove redundant entries; keep only `gemspec` + dev tools |
| `.rspec` | Create | Default RSpec flags |
| `spec/spec_helper.rb` | Modify | SQLite setup, support requires, transaction rollback |
| `spec/support/schema.rb` | Create | In-memory SQLite schema — single source of truth for test DB |
| `spec/support/models.rb` | Create | Minimal AR test models (Article, Post, User) |
| `spec/support/factories.rb` | Create | FactoryBot definitions |
| `lib/docsmith/errors.rb` | Create | Custom exception hierarchy |
| `lib/docsmith/configuration.rb` | Create | `Configuration`, `ClassConfig` DSL, `.resolve` |
| `lib/docsmith/events/event.rb` | Create | `Events::Event` Struct |
| `lib/docsmith/events/hook_registry.rb` | Create | Synchronous callback hooks |
| `lib/docsmith/events/notifier.rb` | Create | AS::Notifications wrapper |
| `lib/docsmith/document.rb` | Create | `Docsmith::Document` AR model |
| `lib/docsmith/document_version.rb` | Create | `Docsmith::DocumentVersion` AR model |
| `lib/docsmith/version_tag.rb` | Create | `Docsmith::VersionTag` AR model |
| `lib/docsmith/auto_save.rb` | Create | Debounce logic |
| `lib/docsmith/version_manager.rb` | Create | `save!`, `restore!`, `tag!` service |
| `lib/docsmith/versionable.rb` | Create | ActiveRecord mixin |
| `lib/docsmith.rb` | Modify | Require all files; expose `Docsmith.configure` |
| `lib/generators/docsmith/install/install_generator.rb` | Create | Rails generator |
| `lib/generators/docsmith/install/templates/create_docsmith_tables.rb.erb` | Create | Migration template |
| `lib/generators/docsmith/install/templates/docsmith_initializer.rb.erb` | Create | Initializer template |

---

## Phase 1: Core Versioning

### Task 1.1 — Gemspec dependencies + Gemfile cleanup

**Files:**
- Modify: `docsmith.gemspec`
- Modify: `Gemfile`

- [ ] **Step 1: Update gemspec**

```ruby
# docsmith.gemspec — replace the commented-out dependency block with:
spec.add_dependency "activerecord",  ">= 7.0"
spec.add_dependency "activesupport", ">= 7.0"
spec.add_dependency "diff-lcs",      "~> 1.5"

spec.add_development_dependency "rspec",       "~> 3.12"
spec.add_development_dependency "sqlite3",     "~> 1.4"
spec.add_development_dependency "factory_bot", "~> 6.0"
spec.add_development_dependency "rubocop",     "~> 1.50"
```

- [ ] **Step 2: Clean up Gemfile** (remove the redundant gem lines — gemspec handles them)

```ruby
# Gemfile — full file:
# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rake", "~> 13.0"
gem "irb"
```

- [ ] **Step 3: Install**

```bash
bundle install
```

Expected: resolves without errors.

- [ ] **Step 4: Commit**

```bash
git add docsmith.gemspec Gemfile Gemfile.lock
git commit -m "feat(deps): add runtime and development dependencies to gemspec

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.2 — .rspec + spec_helper foundation

**Files:**
- Create: `.rspec`
- Modify: `spec/spec_helper.rb`

- [ ] **Step 1: Create `.rspec`**

```
--require spec_helper
--format documentation
--color
```

- [ ] **Step 2: Write spec_helper**

```ruby
# spec/spec_helper.rb
# frozen_string_literal: true

require "active_record"
require "active_support"
require "active_support/core_ext/numeric/time"
require "factory_bot"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.logger = nil

require "docsmith"

require_relative "support/schema"
require_relative "support/models"
require_relative "support/factories"

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  config.around(:each) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end

  # Reset global Docsmith config between examples so hooks/settings don't bleed.
  config.before(:each) { Docsmith.reset_configuration! }

  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = ".rspec_status"
end
```

- [ ] **Step 3: Verify RSpec loads (will error on missing support files — that's expected)**

```bash
bundle exec rspec --dry-run 2>&1 | head -20
```

Expected: error about missing `support/schema` — that's correct, we haven't created it yet.

- [ ] **Step 4: Commit**

```bash
git add .rspec spec/spec_helper.rb
git commit -m "test(infra): add .rspec flags and spec_helper with SQLite + FactoryBot setup

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.3 — Test schema

**Files:**
- Create: `spec/support/schema.rb`
- Create: `spec/docsmith/.gitkeep` (ensure directory exists)

- [ ] **Step 1: Write schema**

```ruby
# spec/support/schema.rb
# frozen_string_literal: true

# In-memory SQLite schema for tests.
# Must mirror db/migrate/create_docsmith_tables.rb exactly.
# SQLite does not support :jsonb — use :text for metadata columns.
# Production migration uses :jsonb for PostgreSQL.

ActiveRecord::Schema.define do
  create_table :docsmith_documents, force: true do |t|
    t.string   :title
    t.text     :content
    t.string   :content_type,       null: false, default: "markdown"
    t.integer  :versions_count,     null: false, default: 0
    t.datetime :last_versioned_at
    t.string   :subject_type
    t.bigint   :subject_id
    t.text     :metadata,           default: "{}"
    t.timestamps
  end
  add_index :docsmith_documents, %i[subject_type subject_id]

  create_table :docsmith_versions, force: true do |t|
    t.bigint   :document_id,      null: false
    t.integer  :version_number,   null: false
    t.text     :content,          null: false
    t.string   :content_type,     null: false
    t.string   :author_type
    t.bigint   :author_id
    t.string   :change_summary
    t.text     :metadata,         default: "{}"
    t.datetime :created_at,       null: false
  end
  add_index :docsmith_versions, %i[document_id version_number], unique: true
  add_index :docsmith_versions, %i[author_type author_id]

  create_table :docsmith_version_tags, force: true do |t|
    t.bigint   :document_id,   null: false
    t.bigint   :version_id,    null: false
    t.string   :name,          null: false
    t.string   :author_type
    t.bigint   :author_id
    t.datetime :created_at,    null: false
  end
  add_index :docsmith_version_tags, %i[document_id name], unique: true
  add_index :docsmith_version_tags, [:version_id]

  create_table :articles, force: true do |t|
    t.string :title
    t.text   :body
    t.timestamps
  end

  create_table :posts, force: true do |t|
    t.text :body
    t.timestamps
  end

  create_table :users, force: true do |t|
    t.string :name
    t.timestamps
  end
end
```

- [ ] **Step 2: Commit**

```bash
mkdir -p spec/docsmith
git add spec/support/schema.rb spec/docsmith/
git commit -m "test(schema): add in-memory SQLite schema for test suite

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.4 — Test models + FactoryBot factories

**Files:**
- Create: `spec/support/models.rb`
- Create: `spec/support/factories.rb`

- [ ] **Step 1: Write test models**

```ruby
# spec/support/models.rb
# frozen_string_literal: true

class Article < ActiveRecord::Base
  include Docsmith::Versionable

  docsmith_config do
    content_field :body
    content_type  :markdown
  end
end

class Post < ActiveRecord::Base
  include Docsmith::Versionable
  # uses all gem defaults (content_field: :body, content_type: :markdown)
end

class User < ActiveRecord::Base; end
```

- [ ] **Step 2: Write factories**

```ruby
# spec/support/factories.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :article do
    title { "Sample Article" }
    body  { "# Hello\n\nInitial content." }
  end

  factory :post do
    body { "Default post body." }
  end

  factory :user do
    name { "Test User" }
  end

  factory :docsmith_document, class: "Docsmith::Document" do
    title        { "Test Document" }
    content      { "# Hello\n\nContent here." }
    content_type { "markdown" }
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add spec/support/models.rb spec/support/factories.rb
git commit -m "test(support): add AR test models and FactoryBot factories

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.5 — Error classes

**Files:**
- Create: `lib/docsmith/errors.rb`
- Create: `spec/docsmith/errors_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/errors_spec.rb
# frozen_string_literal: true

RSpec.describe "Docsmith error hierarchy" do
  it "all errors inherit from Docsmith::Error" do
    expect(Docsmith::InvalidContentField.ancestors).to include(Docsmith::Error)
    expect(Docsmith::MaxVersionsExceeded.ancestors).to include(Docsmith::Error)
    expect(Docsmith::VersionNotFound.ancestors).to include(Docsmith::Error)
    expect(Docsmith::TagAlreadyExists.ancestors).to include(Docsmith::Error)
  end

  it "Docsmith::Error inherits from StandardError" do
    expect(Docsmith::Error.ancestors).to include(StandardError)
  end

  it "can be raised and rescued as StandardError" do
    expect { raise Docsmith::InvalidContentField, "bad" }.to raise_error(StandardError, "bad")
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/errors_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::InvalidContentField`

- [ ] **Step 3: Implement**

```ruby
# lib/docsmith/errors.rb
# frozen_string_literal: true

module Docsmith
  # Base class for all Docsmith errors.
  class Error < StandardError; end

  # Raised when content_field returns a non-String and no content_extractor is configured.
  class InvalidContentField < Error; end

  # Raised when max_versions is set, all versions are tagged, and a new version would exceed the limit.
  class MaxVersionsExceeded < Error; end

  # Raised when a requested version_number does not exist on the document.
  class VersionNotFound < Error; end

  # Raised when tag_version! is called with a name already used on this document.
  class TagAlreadyExists < Error; end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/errors_spec.rb
```

Expected: `3 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/errors.rb spec/docsmith/errors_spec.rb
git commit -m "feat(errors): add custom exception hierarchy

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.6 — ClassConfig DSL + Configuration::DEFAULTS

**Files:**
- Create: `lib/docsmith/configuration.rb`
- Create: `spec/docsmith/configuration_spec.rb` (partial — DEFAULTS and ClassConfig)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/configuration_spec.rb
# frozen_string_literal: true

RSpec.describe Docsmith::Configuration do
  describe "DEFAULTS" do
    it "has expected keys and values" do
      expect(Docsmith::Configuration::DEFAULTS).to eq(
        content_field:     :body,
        content_type:      :markdown,
        auto_save:         true,
        debounce:          30,
        max_versions:      nil,
        content_extractor: nil
      )
    end

    it "is frozen" do
      expect(Docsmith::Configuration::DEFAULTS).to be_frozen
    end
  end
end

RSpec.describe Docsmith::ClassConfig do
  subject(:config) { described_class.new }

  it "starts with empty settings" do
    expect(config.settings).to eq({})
  end

  it "stores content_field setting" do
    config.content_field(:body)
    expect(config.settings[:content_field]).to eq(:body)
  end

  it "stores content_type setting" do
    config.content_type(:html)
    expect(config.settings[:content_type]).to eq(:html)
  end

  it "stores debounce accepting ActiveSupport::Duration" do
    config.debounce(60.seconds)
    expect(config.settings[:debounce]).to eq(60.seconds)
  end

  it "stores max_versions" do
    config.max_versions(10)
    expect(config.settings[:max_versions]).to eq(10)
  end

  it "stores auto_save" do
    config.auto_save(false)
    expect(config.settings[:auto_save]).to eq(false)
  end

  it "stores content_extractor proc" do
    extractor = ->(r) { r.body }
    config.content_extractor(extractor)
    expect(config.settings[:content_extractor]).to eq(extractor)
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/configuration_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Configuration`

- [ ] **Step 3: Implement ClassConfig + DEFAULTS**

```ruby
# lib/docsmith/configuration.rb
# frozen_string_literal: true

module Docsmith
  # DSL object for per-class docsmith_config blocks.
  # Each method call stores a key in @settings.
  # Resolution against global config happens at read time via Configuration.resolve.
  class ClassConfig
    KEYS = %i[content_field content_type auto_save debounce max_versions content_extractor].freeze

    # @return [Hash] raw settings set in this block
    attr_reader :settings

    def initialize
      @settings = {}
    end

    KEYS.each do |key|
      define_method(key) { |val| @settings[key] = val }
    end
  end

  # Global configuration object. Set via Docsmith.configure { |c| ... }.
  class Configuration
    # Gem-level defaults — final fallback in resolution order.
    # debounce stored as Integer (seconds); Duration values normalized via .to_i at resolve time.
    DEFAULTS = {
      content_field:     :body,
      content_type:      :markdown,
      auto_save:         true,
      debounce:          30,
      max_versions:      nil,
      content_extractor: nil
    }.freeze

    # Maps ClassConfig keys to their global Configuration attribute names.
    GLOBAL_KEY_MAP = {
      content_field:     :default_content_field,
      content_type:      :default_content_type,
      auto_save:         :auto_save,
      debounce:          :default_debounce,
      max_versions:      :max_versions,
      content_extractor: :content_extractor
    }.freeze

    attr_accessor :default_content_field, :default_content_type, :auto_save,
                  :default_debounce, :max_versions, :content_extractor,
                  :table_prefix, :diff_context_lines

    def initialize
      @default_content_field = DEFAULTS[:content_field]
      @default_content_type  = DEFAULTS[:content_type]
      @auto_save             = DEFAULTS[:auto_save]
      @default_debounce      = DEFAULTS[:debounce]
      @max_versions          = DEFAULTS[:max_versions]
      @content_extractor     = DEFAULTS[:content_extractor]
      @table_prefix          = "docsmith"
      @diff_context_lines    = 3
      @hooks                 = Hash.new { |h, k| h[k] = [] }
    end

    # Register a synchronous callback for a named event.
    # @param event_name [Symbol] e.g. :version_created
    # @yield [Docsmith::Events::Event]
    def on(event_name, &block)
      @hooks[event_name] << block
    end

    # @param event_name [Symbol]
    # @return [Array<Proc>]
    def hooks_for(event_name)
      @hooks[event_name]
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/configuration_spec.rb
```

Expected: `9 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/configuration.rb spec/docsmith/configuration_spec.rb
git commit -m "feat(config): add ClassConfig DSL and Configuration with DEFAULTS

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.7 — Configuration.resolve + Docsmith.configure

**Files:**
- Modify: `lib/docsmith/configuration.rb` (add `.resolve`)
- Modify: `lib/docsmith.rb` (add `configure`, `configuration`, `reset_configuration!`)
- Modify: `spec/docsmith/configuration_spec.rb` (add resolve specs)

- [ ] **Step 1: Write the failing tests** (append to configuration_spec.rb)

```ruby
# Append to spec/docsmith/configuration_spec.rb

RSpec.describe "Docsmith.configure" do
  it "yields the global configuration object" do
    Docsmith.configure { |c| c.default_content_type = :html }
    expect(Docsmith.configuration.default_content_type).to eq(:html)
  end

  it "reset_configuration! restores defaults" do
    Docsmith.configure { |c| c.default_content_type = :html }
    Docsmith.reset_configuration!
    expect(Docsmith.configuration.default_content_type).to eq(:markdown)
  end
end

RSpec.describe Docsmith::Configuration, ".resolve" do
  let(:global) { Docsmith::Configuration.new }

  it "returns gem defaults when both class and global are empty" do
    result = described_class.resolve({}, global)
    expect(result[:content_field]).to eq(:body)
    expect(result[:content_type]).to eq(:markdown)
    expect(result[:debounce]).to eq(30)
    expect(result[:auto_save]).to eq(true)
    expect(result[:max_versions]).to be_nil
  end

  it "per-class setting overrides global" do
    global.default_content_type = :html
    result = described_class.resolve({ content_type: :json }, global)
    expect(result[:content_type]).to eq(:json)
  end

  it "global setting overrides gem default" do
    global.default_content_type = :html
    result = described_class.resolve({}, global)
    expect(result[:content_type]).to eq(:html)
  end

  it "normalizes debounce ActiveSupport::Duration to Integer" do
    result = described_class.resolve({ debounce: 60.seconds }, global)
    expect(result[:debounce]).to eq(60)
    expect(result[:debounce]).to be_a(Integer)
  end

  it "per-class false for auto_save is not overridden by global true" do
    global.auto_save = true
    result = described_class.resolve({ auto_save: false }, global)
    expect(result[:auto_save]).to eq(false)
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/configuration_spec.rb -e "resolve"
```

Expected: `NoMethodError: undefined method 'resolve'`

- [ ] **Step 3: Add `.resolve` to Configuration**

```ruby
# Add inside class Configuration in lib/docsmith/configuration.rb:

# Merge per-class settings over global config over gem defaults.
# Resolution is at read time — global changes after class definition still apply
# for keys the class does not override.
# @param class_settings [Hash]
# @param global_config [Docsmith::Configuration, nil]
# @return [Hash] fully resolved config
def self.resolve(class_settings, global_config)
  DEFAULTS.each_with_object({}) do |(key, default_val), result|
    global_key = GLOBAL_KEY_MAP[key]
    global_val = global_config&.public_send(global_key)

    result[key] = if class_settings.key?(key)
                    class_settings[key]
                  elsif !global_val.nil?
                    global_val
                  else
                    default_val
                  end
  end.tap { |r| r[:debounce] = r[:debounce].to_i }
end
```

- [ ] **Step 4: Update lib/docsmith.rb** (minimal — just enough to get `Docsmith.configure` working)

```ruby
# lib/docsmith.rb
# frozen_string_literal: true

require_relative "docsmith/version"
require_relative "docsmith/errors"
require_relative "docsmith/configuration"

module Docsmith
  class << self
    # @yield [Docsmith::Configuration]
    def configure
      yield configuration
    end

    # @return [Docsmith::Configuration]
    def configuration
      @configuration ||= Configuration.new
    end

    # Reset to defaults. Called in specs via config.before(:each).
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
```

- [ ] **Step 5: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/configuration_spec.rb
```

Expected: `16 examples, 0 failures`

- [ ] **Step 6: Commit**

```bash
git add lib/docsmith/configuration.rb lib/docsmith.rb spec/docsmith/configuration_spec.rb
git commit -m "feat(config): add Configuration.resolve with precedence chain and Docsmith.configure

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.8 — Events::Event

**Files:**
- Create: `lib/docsmith/events/event.rb`
- Create: `spec/docsmith/events/event_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/events/event_spec.rb
# frozen_string_literal: true

RSpec.describe Docsmith::Events::Event do
  it "is a Struct with keyword_init" do
    event = described_class.new(record: "r", document: "d", version: "v", author: "a")
    expect(event.record).to eq("r")
    expect(event.document).to eq("d")
    expect(event.version).to eq("v")
    expect(event.author).to eq("a")
  end

  it "accepts optional fields" do
    event = described_class.new(
      record: "r", document: "d", version: "v", author: "a",
      from_version: "fv", tag_name: "t1"
    )
    expect(event.from_version).to eq("fv")
    expect(event.tag_name).to eq("t1")
  end

  it "defaults optional fields to nil" do
    event = described_class.new(record: "r", document: "d", version: "v", author: "a")
    expect(event.from_version).to be_nil
    expect(event.tag_name).to be_nil
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/events/event_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Events`

- [ ] **Step 3: Implement**

```ruby
# lib/docsmith/events/event.rb
# frozen_string_literal: true

module Docsmith
  module Events
    # Immutable payload for all Docsmith events.
    # Fields on every event: record, document, version, author.
    # Extra fields by event:
    #   version_restored → from_version
    #   version_tagged   → tag_name
    #   comment_added/orphaned → comment  (Phase 3)
    #   branch_created/merged  → branch   (Phase 4)
    Event = Struct.new(
      :record, :document, :version, :author,
      :from_version, :tag_name,
      :comment, :branch, :conflicts,
      keyword_init: true
    )
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/events/event_spec.rb
```

Expected: `3 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
mkdir -p spec/docsmith/events
git add lib/docsmith/events/event.rb spec/docsmith/events/event_spec.rb
git commit -m "feat(events): add Events::Event struct

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.9 — Events::HookRegistry + Events::Notifier

**Files:**
- Create: `lib/docsmith/events/hook_registry.rb`
- Create: `lib/docsmith/events/notifier.rb`
- Create: `spec/docsmith/events/notifier_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/events/notifier_spec.rb
# frozen_string_literal: true

RSpec.describe Docsmith::Events::Notifier do
  let(:doc)     { instance_double("Docsmith::Document") }
  let(:version) { instance_double("Docsmith::DocumentVersion") }
  let(:author)  { instance_double("User") }

  describe ".instrument" do
    it "fires the registered hook synchronously" do
      received = nil
      Docsmith.configure { |c| c.on(:version_created) { |e| received = e } }

      described_class.instrument(:version_created,
        record: doc, document: doc, version: version, author: author)

      expect(received).to be_a(Docsmith::Events::Event)
      expect(received.version).to eq(version)
    end

    it "publishes to ActiveSupport::Notifications" do
      payload_received = nil
      ActiveSupport::Notifications.subscribe("version_created.docsmith") do |_name, _start, _finish, _id, payload|
        payload_received = payload
      end

      described_class.instrument(:version_created,
        record: doc, document: doc, version: version, author: author)

      expect(payload_received).not_to be_nil
    ensure
      ActiveSupport::Notifications.unsubscribe("version_created.docsmith")
    end

    it "returns the Event object" do
      event = described_class.instrument(:version_created,
        record: doc, document: doc, version: version, author: author)
      expect(event).to be_a(Docsmith::Events::Event)
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/events/notifier_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Events::Notifier`

- [ ] **Step 3: Implement HookRegistry**

```ruby
# lib/docsmith/events/hook_registry.rb
# frozen_string_literal: true

module Docsmith
  module Events
    # Calls synchronous hooks registered via Docsmith.configure { |c| c.on(:event) { } }.
    module HookRegistry
      # @param event_name [Symbol]
      # @param event [Docsmith::Events::Event]
      def self.call(event_name, event)
        Docsmith.configuration.hooks_for(event_name).each { |hook| hook.call(event) }
      end
    end
  end
end
```

- [ ] **Step 4: Implement Notifier**

```ruby
# lib/docsmith/events/notifier.rb
# frozen_string_literal: true

require "active_support/notifications"

module Docsmith
  module Events
    # Fires both AS::Notifications and callback hooks for every action.
    # Instrument name format: "#{event_name}.docsmith" (e.g. "version_created.docsmith").
    module Notifier
      # @param event_name [Symbol]
      # @param payload [Hash] keyword args forwarded to Event.new
      # @return [Docsmith::Events::Event]
      def self.instrument(event_name, **payload)
        event = Event.new(**payload)
        ActiveSupport::Notifications.instrument("#{event_name}.docsmith", payload) do
          HookRegistry.call(event_name, event)
        end
        event
      end
    end
  end
end
```

- [ ] **Step 5: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/events/notifier_spec.rb
```

Expected: `3 examples, 0 failures`

- [ ] **Step 6: Commit**

```bash
git add lib/docsmith/events/hook_registry.rb lib/docsmith/events/notifier.rb \
        spec/docsmith/events/notifier_spec.rb
git commit -m "feat(events): add HookRegistry and Notifier (hooks + AS::Notifications)

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.10 — Docsmith::Document AR model

**Files:**
- Create: `lib/docsmith/document.rb`
- Create: `spec/docsmith/document_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/document_spec.rb
# frozen_string_literal: true

RSpec.describe Docsmith::Document do
  describe "table name" do
    it { expect(described_class.table_name).to eq("docsmith_documents") }
  end

  describe "associations" do
    it "has many document_versions" do
      doc = create(:docsmith_document)
      expect(doc).to respond_to(:document_versions)
    end
  end

  describe "validations" do
    it "requires content_type" do
      doc = build(:docsmith_document, content_type: nil)
      expect(doc).not_to be_valid
    end

    it "rejects unknown content_type" do
      doc = build(:docsmith_document, content_type: "pdf")
      expect(doc).not_to be_valid
    end

    it "accepts html, markdown, json" do
      %w[html markdown json].each do |ct|
        doc = build(:docsmith_document, content_type: ct)
        expect(doc).to be_valid
      end
    end
  end

  describe ".from_record" do
    let(:article) { create(:article) }

    it "creates a shadow document linked to the record" do
      doc = described_class.from_record(article)
      expect(doc).to be_persisted
      expect(doc.subject).to eq(article)
    end

    it "returns same document on second call (find-or-create)" do
      doc1 = described_class.from_record(article)
      doc2 = described_class.from_record(article)
      expect(doc1.id).to eq(doc2.id)
    end

    it "sets content_type to markdown by default" do
      doc = described_class.from_record(article)
      expect(doc.content_type).to eq("markdown")
    end

    it "uses the record's title if it responds to title" do
      doc = described_class.from_record(article)
      expect(doc.title).to eq(article.title)
    end
  end

  describe "#current_version" do
    it "returns nil when no versions exist" do
      doc = create(:docsmith_document)
      expect(doc.current_version).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/document_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Document`

- [ ] **Step 3: Implement**

```ruby
# lib/docsmith/document.rb
# frozen_string_literal: true

module Docsmith
  # AR model backed by docsmith_documents.
  # Serves as both a standalone versioned document and the shadow record
  # auto-created when Docsmith::Versionable is included on any AR model.
  #
  # Shadow record lifecycle:
  #   include Docsmith::Versionable on Article → first save_version! call does:
  #     Docsmith::Document.find_or_create_by!(subject: article_instance)
  #   subject_type / subject_id link back to the originating record.
  class Document < ActiveRecord::Base
    self.table_name = "docsmith_documents"

    belongs_to :subject, polymorphic: true, optional: true
    has_many :document_versions,
             -> { order(:version_number) },
             foreign_key: :document_id,
             class_name:  "Docsmith::DocumentVersion",
             dependent:   :destroy
    has_many :version_tags,
             through:    :document_versions,
             class_name: "Docsmith::VersionTag"

    validates :content_type, presence: true,
              inclusion: { in: %w[html markdown json] }

    # @return [Docsmith::DocumentVersion, nil] latest version by version_number
    def current_version
      document_versions.last
    end

    # Find or create the shadow Document for an existing AR record.
    # @param record [ActiveRecord::Base]
    # @param field [Symbol, nil] ignored — content_field comes from class config
    # @return [Docsmith::Document]
    def self.from_record(record, field: nil)
      find_or_create_by!(subject: record) do |doc|
        doc.content_type = "markdown"
        doc.title = record.respond_to?(:title) ? record.title.to_s : record.class.name
      end
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/document_spec.rb
```

Expected: `9 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/document.rb spec/docsmith/document_spec.rb
git commit -m "feat(models): add Docsmith::Document AR model with from_record

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.11 — Docsmith::DocumentVersion AR model

**Files:**
- Create: `lib/docsmith/document_version.rb`
- Create: `spec/docsmith/document_version_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/document_version_spec.rb
# frozen_string_literal: true

RSpec.describe Docsmith::DocumentVersion do
  let(:doc)  { create(:docsmith_document) }
  let(:user) { create(:user) }

  describe "table name" do
    it { expect(described_class.table_name).to eq("docsmith_versions") }
  end

  describe "validations" do
    it "requires version_number" do
      v = described_class.new(document: doc, content: "x", content_type: "markdown")
      expect(v).not_to be_valid
    end

    it "requires content" do
      v = described_class.new(document: doc, version_number: 1, content_type: "markdown")
      expect(v).not_to be_valid
    end

    it "requires unique version_number per document" do
      described_class.create!(document: doc, version_number: 1, content: "v1",
                               content_type: "markdown", created_at: Time.current)
      dup = described_class.new(document: doc, version_number: 1, content: "v2",
                                content_type: "markdown")
      expect(dup).not_to be_valid
    end
  end

  describe "associations" do
    it "belongs to document" do
      v = described_class.new(document: doc, version_number: 1,
                              content: "hi", content_type: "markdown",
                              created_at: Time.current)
      expect(v.document).to eq(doc)
    end
  end

  describe "#previous_version" do
    it "returns nil for the first version" do
      v1 = described_class.create!(document: doc, version_number: 1, content: "v1",
                                   content_type: "markdown", created_at: Time.current)
      expect(v1.previous_version).to be_nil
    end

    it "returns v1 when called on v2" do
      v1 = described_class.create!(document: doc, version_number: 1, content: "v1",
                                   content_type: "markdown", created_at: Time.current)
      v2 = described_class.create!(document: doc, version_number: 2, content: "v2",
                                   content_type: "markdown", created_at: Time.current)
      expect(v2.previous_version).to eq(v1)
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/document_version_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::DocumentVersion`

- [ ] **Step 3: Implement**

```ruby
# lib/docsmith/document_version.rb
# frozen_string_literal: true

module Docsmith
  # Immutable content snapshot. Table is docsmith_versions.
  # Class name is DocumentVersion (not Version) to avoid colliding with
  # lib/docsmith/version.rb which holds the Docsmith::VERSION constant.
  class DocumentVersion < ActiveRecord::Base
    self.table_name = "docsmith_versions"

    belongs_to :document,
               class_name:  "Docsmith::Document",
               foreign_key: :document_id
    belongs_to :author, polymorphic: true, optional: true
    has_many   :version_tags,
               class_name:  "Docsmith::VersionTag",
               foreign_key: :version_id,
               dependent:   :destroy

    validates :version_number, presence: true,
              uniqueness: { scope: :document_id }
    validates :content,      presence: true
    validates :content_type, presence: true,
              inclusion: { in: %w[html markdown json] }

    # @return [Docsmith::DocumentVersion, nil]
    def previous_version
      document.document_versions
              .where("version_number < ?", version_number)
              .last
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/document_version_spec.rb
```

Expected: `7 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/document_version.rb spec/docsmith/document_version_spec.rb
git commit -m "feat(models): add Docsmith::DocumentVersion AR model (table: docsmith_versions)

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.12 — Docsmith::VersionTag AR model

**Files:**
- Create: `lib/docsmith/version_tag.rb`
- Create: `spec/docsmith/version_tag_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/version_tag_spec.rb
# frozen_string_literal: true

RSpec.describe Docsmith::VersionTag do
  let(:doc)  { create(:docsmith_document) }
  let(:ver)  do
    Docsmith::DocumentVersion.create!(
      document: doc, version_number: 1, content: "v1",
      content_type: "markdown", created_at: Time.current
    )
  end

  describe "table name" do
    it { expect(described_class.table_name).to eq("docsmith_version_tags") }
  end

  describe "validations" do
    it "requires name" do
      tag = described_class.new(document: doc, version: ver)
      expect(tag).not_to be_valid
    end

    it "enforces tag name uniqueness per document (not per version)" do
      described_class.create!(document: doc, version: ver, name: "v1.0",
                               created_at: Time.current)
      dup = described_class.new(document: doc, version: ver, name: "v1.0")
      expect(dup).not_to be_valid
    end

    it "allows same tag name on different documents" do
      doc2 = create(:docsmith_document)
      ver2 = Docsmith::DocumentVersion.create!(
        document: doc2, version_number: 1, content: "v1",
        content_type: "markdown", created_at: Time.current
      )
      described_class.create!(document: doc, version: ver, name: "v1.0",
                               created_at: Time.current)
      tag2 = described_class.new(document: doc2, version: ver2, name: "v1.0")
      expect(tag2).to be_valid
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/version_tag_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::VersionTag`

- [ ] **Step 3: Implement**

```ruby
# lib/docsmith/version_tag.rb
# frozen_string_literal: true

module Docsmith
  # Named label on a DocumentVersion.
  # Tag names are unique per document (not per version) — enforced at DB level
  # via the unique index on [document_id, name] in docsmith_version_tags.
  # document_id is denormalized on this table to enable that DB-level constraint.
  class VersionTag < ActiveRecord::Base
    self.table_name = "docsmith_version_tags"

    belongs_to :document,
               class_name:  "Docsmith::Document",
               foreign_key: :document_id
    belongs_to :version,
               class_name:  "Docsmith::DocumentVersion",
               foreign_key: :version_id
    belongs_to :author, polymorphic: true, optional: true

    validates :name,        presence: true
    validates :document_id, presence: true
    validates :version_id,  presence: true
    validates :name, uniqueness: { scope: :document_id,
                                   message: "already exists on this document" }
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/version_tag_spec.rb
```

Expected: `4 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/version_tag.rb spec/docsmith/version_tag_spec.rb
git commit -m "feat(models): add Docsmith::VersionTag AR model

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.13 — Docsmith::AutoSave (debounce)

**Files:**
- Create: `lib/docsmith/auto_save.rb`
- Create: `spec/docsmith/auto_save_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/auto_save_spec.rb
# frozen_string_literal: true

RSpec.describe Docsmith::AutoSave do
  let(:doc)    { create(:docsmith_document, content: "hello") }
  let(:config) { { debounce: 30, auto_save: true, max_versions: nil, content_extractor: nil } }

  describe ".within_debounce?" do
    it "returns false when last_versioned_at is nil" do
      doc.update_column(:last_versioned_at, nil)
      expect(described_class.within_debounce?(doc, config)).to eq(false)
    end

    it "returns true when last saved less than debounce seconds ago" do
      doc.update_column(:last_versioned_at, 10.seconds.ago)
      expect(described_class.within_debounce?(doc, config)).to eq(true)
    end

    it "returns false when last saved more than debounce seconds ago" do
      doc.update_column(:last_versioned_at, 60.seconds.ago)
      expect(described_class.within_debounce?(doc, config)).to eq(false)
    end

    it "normalizes Duration debounce to integer" do
      config_with_duration = config.merge(debounce: 30.seconds)
      doc.update_column(:last_versioned_at, 10.seconds.ago)
      expect(described_class.within_debounce?(doc, config_with_duration)).to eq(true)
    end
  end

  describe ".call" do
    it "returns nil when within debounce window" do
      doc.update_column(:last_versioned_at, 5.seconds.ago)
      result = described_class.call(doc, author: nil, config: config)
      expect(result).to be_nil
    end

    it "delegates to VersionManager.save! outside debounce window" do
      doc.update_column(:last_versioned_at, 60.seconds.ago)
      expect(Docsmith::VersionManager).to receive(:save!).with(doc, author: nil, config: config)
      described_class.call(doc, author: nil, config: config)
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/auto_save_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::AutoSave`

- [ ] **Step 3: Implement**

```ruby
# lib/docsmith/auto_save.rb
# frozen_string_literal: true

module Docsmith
  # Applies debounce logic before delegating to VersionManager.save!
  # Extracted for independent testability.
  module AutoSave
    # @param document [Docsmith::Document]
    # @param author [Object, nil]
    # @param config [Hash] resolved config
    # @return [Docsmith::DocumentVersion, nil] nil if within debounce or content unchanged
    def self.call(document, author:, config:)
      return nil if within_debounce?(document, config)

      VersionManager.save!(document, author: author, config: config)
    end

    # Returns true if the debounce window has not yet elapsed.
    # Public so specs can assert on timing logic without mocking Time.
    # @param document [Docsmith::Document]
    # @param config [Hash] resolved config
    # @return [Boolean]
    def self.within_debounce?(document, config)
      last_saved = document.last_versioned_at
      return false if last_saved.nil?

      Time.current < last_saved + config[:debounce].to_i
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/auto_save_spec.rb
```

Expected: `6 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/auto_save.rb spec/docsmith/auto_save_spec.rb
git commit -m "feat(auto-save): add AutoSave with debounce logic and within_debounce? helper

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.14 — VersionManager.save!

**Files:**
- Create: `lib/docsmith/version_manager.rb`
- Create: `spec/docsmith/version_manager_spec.rb` (save! section)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/version_manager_spec.rb
# frozen_string_literal: true

RSpec.describe Docsmith::VersionManager do
  let(:doc)    { create(:docsmith_document, content: "initial") }
  let(:user)   { create(:user) }
  let(:config) { Docsmith::Configuration.resolve({}, Docsmith.configuration) }

  describe ".save!" do
    it "creates a DocumentVersion with version_number 1 for first save" do
      version = described_class.save!(doc, author: user, config: config)
      expect(version).to be_a(Docsmith::DocumentVersion)
      expect(version.version_number).to eq(1)
      expect(version.content).to eq("initial")
    end

    it "increments version_number on subsequent saves" do
      described_class.save!(doc, author: user, config: config)
      doc.update_column(:content, "version two")
      v2 = described_class.save!(doc, author: user, config: config)
      expect(v2.version_number).to eq(2)
    end

    it "returns nil when content is identical to latest version" do
      described_class.save!(doc, author: user, config: config)
      result = described_class.save!(doc, author: user, config: config)
      expect(result).to be_nil
    end

    it "increments versions_count on document" do
      expect { described_class.save!(doc, author: user, config: config) }
        .to change { doc.reload.versions_count }.from(0).to(1)
    end

    it "sets last_versioned_at on document" do
      expect { described_class.save!(doc, author: user, config: config) }
        .to change { doc.reload.last_versioned_at }.from(nil)
    end

    it "stores the author polymorphically" do
      version = described_class.save!(doc, author: user, config: config)
      expect(version.author).to eq(user)
    end

    it "stores the change_summary" do
      version = described_class.save!(doc, author: user, summary: "Initial draft", config: config)
      expect(version.change_summary).to eq("Initial draft")
    end

    it "fires version_created event with record and document" do
      received = nil
      Docsmith.configure { |c| c.on(:version_created) { |e| received = e } }
      described_class.save!(doc, author: user, config: config)
      expect(received).to be_a(Docsmith::Events::Event)
      expect(received.document).to eq(doc)
      expect(received.author).to eq(user)
    end

    context "when max_versions is set" do
      let(:config) { Docsmith::Configuration.resolve({ max_versions: 2 }, Docsmith.configuration) }

      it "prunes the oldest untagged version when limit exceeded" do
        described_class.save!(doc, author: user, config: config)
        doc.update_column(:content, "v2")
        described_class.save!(doc, author: user, config: config)
        doc.update_column(:content, "v3")
        described_class.save!(doc, author: user, config: config)

        expect(doc.reload.document_versions.pluck(:version_number)).not_to include(1)
      end

      it "raises MaxVersionsExceeded when all versions are tagged" do
        v1 = described_class.save!(doc, author: user, config: config)
        Docsmith::VersionTag.create!(document: doc, version: v1, name: "t1",
                                     created_at: Time.current)
        doc.update_column(:content, "v2")
        v2 = described_class.save!(doc, author: user, config: config)
        Docsmith::VersionTag.create!(document: doc, version: v2, name: "t2",
                                     created_at: Time.current)
        doc.update_column(:content, "v3")

        expect { described_class.save!(doc, author: user, config: config) }
          .to raise_error(Docsmith::MaxVersionsExceeded)
      end
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/version_manager_spec.rb -e "save!"
```

Expected: `NameError: uninitialized constant Docsmith::VersionManager`

- [ ] **Step 3: Implement VersionManager.save!**

```ruby
# lib/docsmith/version_manager.rb
# frozen_string_literal: true

module Docsmith
  # Service object for all version lifecycle operations.
  # The Versionable mixin delegates here after resolving the shadow document.
  # Always receives a Docsmith::Document instance.
  module VersionManager
    # Create a new DocumentVersion snapshot.
    # Returns nil if content is identical to the latest version (string == check).
    #
    # @param document [Docsmith::Document]
    # @param author [Object, nil]
    # @param summary [String, nil]
    # @param config [Hash] resolved config
    # @return [Docsmith::DocumentVersion, nil]
    def self.save!(document, author:, summary: nil, config: nil)
      config  ||= Configuration.resolve({}, Docsmith.configuration)
      current   = document.content.to_s
      latest    = document.document_versions.last

      return nil if latest && latest.content == current

      next_num = document.versions_count + 1

      version = DocumentVersion.create!(
        document:       document,
        version_number: next_num,
        content:        current,
        content_type:   document.content_type,
        author:         author,
        change_summary: summary,
        metadata:       {}
      )

      document.update_columns(
        versions_count:    next_num,
        last_versioned_at: Time.current
      )

      prune_if_needed!(document, config) if config[:max_versions]

      record = document.subject || document
      Events::Notifier.instrument(:version_created,
        record: record, document: document, version: version, author: author)

      version
    end

    def self.prune_if_needed!(document, config)
      max = config[:max_versions]
      return unless max && document.versions_count > max

      tagged_ids      = VersionTag.where(document_id: document.id).select(:version_id)
      oldest_untagged = document.document_versions.where.not(id: tagged_ids).first

      unless oldest_untagged
        raise MaxVersionsExceeded,
          "All #{document.versions_count} versions are tagged. Cannot prune to stay within " \
          "max_versions: #{max}. Remove a tag or increase max_versions."
      end

      oldest_untagged.destroy!
      document.update_column(:versions_count, document.versions_count - 1)
    end
    private_class_method :prune_if_needed!
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/version_manager_spec.rb -e "save!"
```

Expected: `10 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/version_manager.rb spec/docsmith/version_manager_spec.rb
git commit -m "feat(version-manager): add VersionManager.save! with pruning and events

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.15 — VersionManager.restore! + VersionManager.tag!

**Files:**
- Modify: `lib/docsmith/version_manager.rb`
- Modify: `spec/docsmith/version_manager_spec.rb`

- [ ] **Step 1: Write failing tests** (append to version_manager_spec.rb)

```ruby
# Append to spec/docsmith/version_manager_spec.rb

describe ".restore!" do
  before do
    described_class.save!(doc, author: user, config: config)
    doc.update_column(:content, "version two")
    described_class.save!(doc, author: user, config: config)
  end

  it "creates a new version with the old content" do
    new_ver = described_class.restore!(doc, version: 1, author: user, config: config)
    expect(new_ver.content).to eq("initial")
    expect(new_ver.version_number).to eq(3)
  end

  it "updates document.content to the restored content" do
    described_class.restore!(doc, version: 1, author: user, config: config)
    expect(doc.reload.content).to eq("initial")
  end

  it "sets change_summary to Restored from vN" do
    new_ver = described_class.restore!(doc, version: 1, author: user, config: config)
    expect(new_ver.change_summary).to eq("Restored from v1")
  end

  it "fires version_restored event (not version_created)" do
    events = []
    Docsmith.configure do |c|
      c.on(:version_created)  { |e| events << :created }
      c.on(:version_restored) { |e| events << :restored }
    end
    described_class.restore!(doc, version: 1, author: user, config: config)
    expect(events).to eq([:restored])
  end

  it "raises VersionNotFound for unknown version number" do
    expect { described_class.restore!(doc, version: 99, author: user, config: config) }
      .to raise_error(Docsmith::VersionNotFound)
  end
end

describe ".tag!" do
  before { described_class.save!(doc, author: user, config: config) }

  it "creates a VersionTag for the given version number" do
    tag = described_class.tag!(doc, version: 1, name: "v1.0", author: user)
    expect(tag).to be_a(Docsmith::VersionTag)
    expect(tag.name).to eq("v1.0")
  end

  it "fires version_tagged event" do
    received = nil
    Docsmith.configure { |c| c.on(:version_tagged) { |e| received = e } }
    described_class.tag!(doc, version: 1, name: "release", author: user)
    expect(received.tag_name).to eq("release")
  end

  it "raises TagAlreadyExists if name is reused on same document" do
    described_class.tag!(doc, version: 1, name: "v1.0", author: user)
    expect { described_class.tag!(doc, version: 1, name: "v1.0", author: user) }
      .to raise_error(Docsmith::TagAlreadyExists)
  end

  it "raises VersionNotFound for unknown version number" do
    expect { described_class.tag!(doc, version: 99, name: "x", author: user) }
      .to raise_error(Docsmith::VersionNotFound)
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/version_manager_spec.rb -e "restore!"
bundle exec rspec spec/docsmith/version_manager_spec.rb -e "tag!"
```

Expected: `NoMethodError: undefined method 'restore!'`

- [ ] **Step 3: Add restore! and tag! to version_manager.rb**

```ruby
# Add to lib/docsmith/version_manager.rb inside the module:

# Restore a previous version by creating a new version with its content.
# Fires :version_restored (not :version_created). Never mutates existing versions.
#
# @param document [Docsmith::Document]
# @param version [Integer] version_number to restore from
# @param author [Object, nil]
# @param config [Hash] resolved config
# @return [Docsmith::DocumentVersion] the new version
# @raise [Docsmith::VersionNotFound]
def self.restore!(document, version:, author:, config: nil)
  config      ||= Configuration.resolve({}, Docsmith.configuration)
  from_version  = document.document_versions.find_by(version_number: version)
  raise VersionNotFound, "Version #{version} not found on this document" unless from_version

  next_num = document.versions_count + 1

  new_version = DocumentVersion.create!(
    document:       document,
    version_number: next_num,
    content:        from_version.content,
    content_type:   document.content_type,
    author:         author,
    change_summary: "Restored from v#{version}",
    metadata:       {}
  )

  document.update_columns(
    content:           from_version.content,
    versions_count:    next_num,
    last_versioned_at: Time.current
  )

  record = document.subject || document
  Events::Notifier.instrument(:version_restored,
    record: record, document: document, version: new_version,
    author: author, from_version: from_version)

  new_version
end

# Tag a specific version with a name unique to this document.
#
# @param document [Docsmith::Document]
# @param version [Integer] version_number to tag
# @param name [String] unique per document
# @param author [Object, nil]
# @return [Docsmith::VersionTag]
# @raise [Docsmith::VersionNotFound]
# @raise [Docsmith::TagAlreadyExists]
def self.tag!(document, version:, name:, author:)
  version_record = document.document_versions.find_by(version_number: version)
  raise VersionNotFound, "Version #{version} not found on this document" unless version_record

  if VersionTag.exists?(document_id: document.id, name: name)
    raise TagAlreadyExists, "Tag '#{name}' already exists on this document"
  end

  tag = VersionTag.create!(
    document: document,
    version:  version_record,
    name:     name,
    author:   author
  )

  record = document.subject || document
  Events::Notifier.instrument(:version_tagged,
    record: record, document: document, version: version_record,
    author: author, tag_name: name)

  tag
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/version_manager_spec.rb
```

Expected: `20 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/version_manager.rb spec/docsmith/version_manager_spec.rb
git commit -m "feat(version-manager): add restore! and tag! with events and error handling

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.16 — Versionable: setup, docsmith_config DSL, _docsmith_document

**Files:**
- Create: `lib/docsmith/versionable.rb`
- Create: `spec/docsmith/versionable_spec.rb` (setup + config section)

- [ ] **Step 1: Write failing tests**

```ruby
# spec/docsmith/versionable_spec.rb
# frozen_string_literal: true

RSpec.describe Docsmith::Versionable do
  describe "docsmith_config DSL" do
    it "returns a ClassConfig when called without a block" do
      expect(Article.docsmith_config).to be_a(Docsmith::ClassConfig)
    end

    it "stores content_field and content_type set in the block" do
      expect(Article.docsmith_config.settings[:content_field]).to eq(:body)
      expect(Article.docsmith_config.settings[:content_type]).to eq(:markdown)
    end

    it "resolved config uses per-class settings over defaults" do
      config = Article.docsmith_resolved_config
      expect(config[:content_field]).to eq(:body)
      expect(config[:content_type]).to eq(:markdown)
    end

    it "resolved config falls through to defaults for unset keys" do
      config = Article.docsmith_resolved_config
      expect(config[:debounce]).to eq(30)
    end
  end

  describe "shadow document (_docsmith_document)" do
    let(:article) { create(:article) }

    it "creates a Docsmith::Document on first access" do
      expect { article.send(:_docsmith_document) }
        .to change { Docsmith::Document.count }.by(1)
    end

    it "is idempotent — same document returned on second call" do
      doc1 = article.send(:_docsmith_document)
      doc2 = article.send(:_docsmith_document)
      expect(doc1.id).to eq(doc2.id)
    end

    it "sets subject to the article" do
      doc = article.send(:_docsmith_document)
      expect(doc.subject).to eq(article)
    end

    it "sets content_type from the class config" do
      doc = article.send(:_docsmith_document)
      expect(doc.content_type).to eq("markdown")
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb -e "docsmith_config"
```

Expected: `NoMethodError: undefined method 'docsmith_config'` (Article doesn't have the mixin yet)

- [ ] **Step 3: Implement the mixin skeleton**

```ruby
# lib/docsmith/versionable.rb
# frozen_string_literal: true

module Docsmith
  # ActiveRecord mixin that adds full versioning to any model.
  #
  # Usage:
  #   class Article < ApplicationRecord
  #     include Docsmith::Versionable
  #     docsmith_config { content_field :body; content_type :markdown }
  #   end
  module Versionable
    def self.included(base)
      base.extend(ClassMethods)
      base.after_save(:_docsmith_auto_save_callback)
    end

    module ClassMethods
      # Configure per-class Docsmith options. All keys optional.
      # Unset keys fall through to global config then gem defaults.
      # @yield block evaluated on a Docsmith::ClassConfig instance
      # @return [Docsmith::ClassConfig]
      def docsmith_config(&block)
        @_docsmith_class_config ||= Docsmith::ClassConfig.new
        @_docsmith_class_config.instance_eval(&block) if block_given?
        @_docsmith_class_config
      end

      # @return [Hash] fully resolved config (read-time resolution)
      def docsmith_resolved_config
        Docsmith::Configuration.resolve(
          @_docsmith_class_config&.settings || {},
          Docsmith.configuration
        )
      end
    end

    private

    # Finds or creates the shadow Docsmith::Document for this record.
    # Cached in @_docsmith_document after first lookup.
    def _docsmith_document
      config = self.class.docsmith_resolved_config
      @_docsmith_document ||= Docsmith::Document.find_or_create_by!(subject: self) do |doc|
        doc.content_type = config[:content_type].to_s
        doc.title        = respond_to?(:title) ? title.to_s : self.class.name
      end
    end

    # Placeholder — implemented in Task 1.17
    def _docsmith_auto_save_callback; end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb -e "docsmith_config"
bundle exec rspec spec/docsmith/versionable_spec.rb -e "shadow document"
```

Expected: `8 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/versionable.rb spec/docsmith/versionable_spec.rb
git commit -m "feat(versionable): add mixin skeleton, docsmith_config DSL, and shadow document

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.17 — Versionable: _sync_docsmith_content! + save_version!

**Files:**
- Modify: `lib/docsmith/versionable.rb`
- Modify: `spec/docsmith/versionable_spec.rb`

- [ ] **Step 1: Write failing tests** (append to versionable_spec.rb)

```ruby
# Append to spec/docsmith/versionable_spec.rb

describe "#save_version!" do
  let(:article) { create(:article, body: "# Hello") }

  it "creates a DocumentVersion" do
    expect { article.save_version!(author: nil) }
      .to change { Docsmith::DocumentVersion.count }.by(1)
  end

  it "returns the new DocumentVersion" do
    version = article.save_version!(author: nil)
    expect(version).to be_a(Docsmith::DocumentVersion)
  end

  it "snapshots the content_field value" do
    version = article.save_version!(author: nil)
    expect(version.content).to eq("# Hello")
  end

  it "returns nil when content has not changed since last version" do
    article.save_version!(author: nil)
    expect(article.save_version!(author: nil)).to be_nil
  end

  it "raises InvalidContentField when content_field returns non-String" do
    allow(article).to receive(:body).and_return(42)
    expect { article.save_version!(author: nil) }
      .to raise_error(Docsmith::InvalidContentField, /content_field :body/)
  end

  it "uses content_extractor when configured" do
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "articles"
      include Docsmith::Versionable
      docsmith_config do
        content_field     :body
        content_type      :html
        content_extractor ->(r) { "extracted: #{r.body}" }
      end
    end
    article2 = klass.create!(body: "raw")
    version = article2.save_version!(author: nil)
    expect(version.content).to eq("extracted: raw")
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb -e "save_version!"
```

Expected: `NoMethodError: undefined method 'save_version!'`

- [ ] **Step 3: Add _sync_docsmith_content! and save_version! to versionable.rb**

```ruby
# Add these public methods inside module Versionable (before the private section):

# Create a new DocumentVersion snapshot of this record's content.
# Returns nil if content is identical to the latest version.
# Raises Docsmith::InvalidContentField if content_field returns a non-String
# and no content_extractor is configured.
#
# @param author [Object, nil]
# @param summary [String, nil]
# @return [Docsmith::DocumentVersion, nil]
def save_version!(author:, summary: nil)
  _sync_docsmith_content!
  Docsmith::VersionManager.save!(
    _docsmith_document,
    author:  author,
    summary: summary,
    config:  self.class.docsmith_resolved_config
  )
end

# Add to private section:

# Reads content from the model via content_extractor or content_field,
# validates it is a String, then syncs to the shadow document's content column.
def _sync_docsmith_content!
  config = self.class.docsmith_resolved_config

  raw = if config[:content_extractor]
          config[:content_extractor].call(self)
        else
          public_send(config[:content_field])
        end

  unless raw.nil? || raw.is_a?(String)
    source = config[:content_extractor] ? "content_extractor" : "content_field :#{config[:content_field]}"
    raise Docsmith::InvalidContentField,
      "#{source} must return a String, got #{raw.class}. " \
      "Use content_extractor: ->(record) { ... } for non-string fields."
  end

  _docsmith_document.update_column(:content, raw.to_s)
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb -e "save_version!"
```

Expected: `6 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/versionable.rb spec/docsmith/versionable_spec.rb
git commit -m "feat(versionable): add save_version! and _sync_docsmith_content! with validation

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.18 — Versionable: auto_save_version! + after_save callback

**Files:**
- Modify: `lib/docsmith/versionable.rb`
- Modify: `spec/docsmith/versionable_spec.rb`

- [ ] **Step 1: Write failing tests** (append to versionable_spec.rb)

```ruby
# Append to spec/docsmith/versionable_spec.rb

describe "#auto_save_version!" do
  let(:article) { create(:article, body: "# Auto") }

  it "creates a version outside debounce window" do
    expect { article.auto_save_version!(author: nil) }
      .to change { Docsmith::DocumentVersion.count }.by(1)
  end

  it "returns nil within debounce window" do
    article.auto_save_version!(author: nil)
    result = article.auto_save_version!(author: nil)
    expect(result).to be_nil
  end

  it "returns nil when content is unchanged" do
    article.auto_save_version!(author: nil)
    doc = article.send(:_docsmith_document)
    doc.update_column(:last_versioned_at, 60.seconds.ago)
    result = article.auto_save_version!(author: nil)
    expect(result).to be_nil
  end

  it "returns nil when auto_save is false in config" do
    allow(Article).to receive(:docsmith_resolved_config)
      .and_return(Article.docsmith_resolved_config.merge(auto_save: false))
    expect(article.auto_save_version!(author: nil)).to be_nil
  end
end

describe "after_save callback" do
  it "calls auto_save_version! after every AR save" do
    article = build(:article, body: "callback test")
    expect(article).to receive(:auto_save_version!)
    article.save!
  end

  it "swallows InvalidContentField during auto-save callback" do
    article = create(:article, body: "ok")
    allow(article).to receive(:body).and_return(Object.new)
    expect { article.save! }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb -e "auto_save_version!"
```

Expected: `NoMethodError: undefined method 'auto_save_version!'`

- [ ] **Step 3: Add auto_save_version! and update the callback**

```ruby
# Add public method to Versionable (after save_version!):

# Debounced auto-save. Returns nil if debounce window has not elapsed
# OR content is unchanged. Both non-save cases return nil.
# auto_save: false in config causes this to always return nil.
#
# @param author [Object, nil]
# @return [Docsmith::DocumentVersion, nil]
def auto_save_version!(author: nil)
  config = self.class.docsmith_resolved_config
  return nil unless config[:auto_save]

  _sync_docsmith_content!
  Docsmith::AutoSave.call(_docsmith_document, author: author, config: config)
end

# Replace the placeholder _docsmith_auto_save_callback in private section:
def _docsmith_auto_save_callback
  auto_save_version!
rescue Docsmith::InvalidContentField
  # Swallow on auto-save — user must call save_version! explicitly to see the error.
  nil
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb -e "auto_save_version!"
bundle exec rspec spec/docsmith/versionable_spec.rb -e "after_save"
```

Expected: `6 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/versionable.rb spec/docsmith/versionable_spec.rb
git commit -m "feat(versionable): add auto_save_version! and after_save debounce callback

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.19 — Versionable: query methods

**Files:**
- Modify: `lib/docsmith/versionable.rb`
- Modify: `spec/docsmith/versionable_spec.rb`

- [ ] **Step 1: Write failing tests** (append to versionable_spec.rb)

```ruby
# Append to spec/docsmith/versionable_spec.rb

describe "query methods" do
  let(:article) { create(:article, body: "v1 content") }

  before do
    article.save_version!(author: nil)
    article.update_column(:body, "v2 content")
    article.instance_variable_set(:@_docsmith_document, nil)
    article.send(:_sync_docsmith_content!)
    article.send(:_docsmith_document).update_column(:content, "v2 content")
    article.save_version!(author: nil)
  end

  describe "#versions" do
    it "returns an AR relation of DocumentVersions ordered by version_number" do
      expect(article.versions.count).to eq(2)
      expect(article.versions.first.version_number).to eq(1)
      expect(article.versions.last.version_number).to eq(2)
    end
  end

  describe "#current_version" do
    it "returns the latest DocumentVersion" do
      expect(article.current_version.version_number).to eq(2)
    end
  end

  describe "#version(n)" do
    it "returns the DocumentVersion with that version_number" do
      expect(article.version(1).content).to eq("v1 content")
    end

    it "returns nil for unknown version number" do
      expect(article.version(99)).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb -e "query methods"
```

Expected: `NoMethodError: undefined method 'versions'`

- [ ] **Step 3: Add query methods to Versionable**

```ruby
# Add public methods to Versionable (after auto_save_version!):

# @return [ActiveRecord::Relation<Docsmith::DocumentVersion>] ordered by version_number
def versions
  _docsmith_document.document_versions
end

# @return [Docsmith::DocumentVersion, nil] latest version
def current_version
  _docsmith_document.current_version
end

# @param number [Integer] 1-indexed version_number
# @return [Docsmith::DocumentVersion, nil]
def version(number)
  _docsmith_document.document_versions.find_by(version_number: number)
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb -e "query methods"
```

Expected: `4 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/versionable.rb spec/docsmith/versionable_spec.rb
git commit -m "feat(versionable): add versions, current_version, and version(n) query methods

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.20 — Versionable: restore_version! + tag methods

**Files:**
- Modify: `lib/docsmith/versionable.rb`
- Modify: `spec/docsmith/versionable_spec.rb`

- [ ] **Step 1: Write failing tests** (append to versionable_spec.rb)

```ruby
# Append to spec/docsmith/versionable_spec.rb

describe "#restore_version!" do
  let(:article) { create(:article, body: "original") }

  before do
    article.save_version!(author: nil)
    article.update_columns(body: "edited")
    article.instance_variable_set(:@_docsmith_document, nil)
    article.send(:_docsmith_document).update_column(:content, "edited")
    article.save_version!(author: nil)
  end

  it "creates a new version with the old content" do
    new_ver = article.restore_version!(1, author: nil)
    expect(new_ver.content).to eq("original")
    expect(new_ver.version_number).to eq(3)
  end

  it "syncs restored content back to the model's body column" do
    article.restore_version!(1, author: nil)
    expect(article.reload.body).to eq("original")
  end

  it "raises VersionNotFound for unknown version" do
    expect { article.restore_version!(99, author: nil) }
      .to raise_error(Docsmith::VersionNotFound)
  end
end

describe "tag methods" do
  let(:article) { create(:article, body: "v1") }
  before { article.save_version!(author: nil) }

  describe "#tag_version!" do
    it "creates a VersionTag" do
      expect { article.tag_version!(1, name: "v1.0", author: nil) }
        .to change { Docsmith::VersionTag.count }.by(1)
    end

    it "raises TagAlreadyExists on duplicate name" do
      article.tag_version!(1, name: "v1.0", author: nil)
      expect { article.tag_version!(1, name: "v1.0", author: nil) }
        .to raise_error(Docsmith::TagAlreadyExists)
    end
  end

  describe "#tagged_version" do
    it "returns the DocumentVersion for a given tag" do
      article.tag_version!(1, name: "release", author: nil)
      expect(article.tagged_version("release").version_number).to eq(1)
    end

    it "returns nil for unknown tag" do
      expect(article.tagged_version("nope")).to be_nil
    end
  end

  describe "#version_tags" do
    it "returns array of tag names for a version" do
      article.tag_version!(1, name: "v1.0", author: nil)
      article.tag_version!(1, name: "stable", author: nil)
      expect(article.version_tags(1)).to contain_exactly("v1.0", "stable")
    end

    it "returns empty array for untagged version" do
      expect(article.version_tags(1)).to eq([])
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb -e "restore_version!"
```

Expected: `NoMethodError: undefined method 'restore_version!'`

- [ ] **Step 3: Add restore + tag methods to Versionable**

```ruby
# Add public methods to Versionable (after version(n)):

# Restore to a previous version. Creates a new version with the old content.
# Syncs restored content back to the model's content_field via update_column
# (bypasses after_save to prevent a duplicate auto-save).
# Never mutates existing versions.
#
# @param number [Integer] version_number to restore from
# @param author [Object, nil]
# @return [Docsmith::DocumentVersion]
# @raise [Docsmith::VersionNotFound]
def restore_version!(number, author:)
  result = Docsmith::VersionManager.restore!(
    _docsmith_document,
    version: number,
    author:  author,
    config:  self.class.docsmith_resolved_config
  )
  field = self.class.docsmith_resolved_config[:content_field]
  update_column(field, _docsmith_document.reload.content)
  result
end

# Tag a specific version. Names are unique per document.
# @param number [Integer] version_number to tag
# @param name [String]
# @param author [Object, nil]
# @return [Docsmith::VersionTag]
def tag_version!(number, name:, author:)
  Docsmith::VersionManager.tag!(
    _docsmith_document, version: number, name: name, author: author)
end

# @param tag_name [String]
# @return [Docsmith::DocumentVersion, nil]
def tagged_version(tag_name)
  tag = _docsmith_document.version_tags.find_by(name: tag_name)
  tag&.version
end

# @param number [Integer] version_number
# @return [Array<String>] tag names on that version
def version_tags(number)
  ver = version(number)
  return [] unless ver
  ver.version_tags.pluck(:name)
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb
```

Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/versionable.rb spec/docsmith/versionable_spec.rb
git commit -m "feat(versionable): add restore_version! and tag_version!/tagged_version/version_tags

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.21 — lib/docsmith.rb entry point (wire everything)

**Files:**
- Modify: `lib/docsmith.rb`

- [ ] **Step 1: Update lib/docsmith.rb to require all Phase 1 files**

```ruby
# lib/docsmith.rb
# frozen_string_literal: true

require "active_record"
require "active_support"
require "active_support/core_ext/numeric/time"
require "active_support/notifications"

require_relative "docsmith/version"
require_relative "docsmith/errors"
require_relative "docsmith/configuration"
require_relative "docsmith/events/event"
require_relative "docsmith/events/hook_registry"
require_relative "docsmith/events/notifier"
require_relative "docsmith/document"
require_relative "docsmith/document_version"
require_relative "docsmith/version_tag"
require_relative "docsmith/auto_save"
require_relative "docsmith/version_manager"
require_relative "docsmith/versionable"

module Docsmith
  class << self
    # @yield [Docsmith::Configuration]
    def configure
      yield configuration
    end

    # @return [Docsmith::Configuration]
    def configuration
      @configuration ||= Configuration.new
    end

    # Reset to gem defaults. Call in specs via config.before(:each).
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
```

- [ ] **Step 2: Run the full Phase 1 suite**

```bash
bundle exec rspec spec/docsmith/
```

Expected: all examples pass, 0 failures.

- [ ] **Step 3: Commit**

```bash
git add lib/docsmith.rb
git commit -m "feat(entry): wire all Phase 1 requires in lib/docsmith.rb

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.22 — Generator (rails generate docsmith:install)

**Files:**
- Create: `lib/generators/docsmith/install/install_generator.rb`
- Create: `lib/generators/docsmith/install/templates/create_docsmith_tables.rb.erb`
- Create: `lib/generators/docsmith/install/templates/docsmith_initializer.rb.erb`

- [ ] **Step 1: Create generator** (no test — generators are verified by running them)

```ruby
# lib/generators/docsmith/install/install_generator.rb
# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Docsmith
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Creates the Docsmith migration and initializer."

      def create_migration
        migration_template(
          "create_docsmith_tables.rb.erb",
          "db/migrate/create_docsmith_tables.rb"
        )
      end

      def create_initializer
        template "docsmith_initializer.rb.erb", "config/initializers/docsmith.rb"
      end
    end
  end
end
```

- [ ] **Step 2: Create migration template**

```erb
<%# lib/generators/docsmith/install/templates/create_docsmith_tables.rb.erb %>
# frozen_string_literal: true

class CreateDocsmithTables < ActiveRecord::Migration[<%= ActiveRecord::Migration.current_version %>]
  def change
    create_table :docsmith_documents do |t|
      t.string   :title
      t.text     :content
      t.string   :content_type,       null: false, default: "markdown"
      t.integer  :versions_count,     null: false, default: 0
      t.datetime :last_versioned_at
      t.string   :subject_type
      t.bigint   :subject_id
      t.jsonb    :metadata,           null: false, default: {}
      t.timestamps
    end
    add_index :docsmith_documents, %i[subject_type subject_id]

    create_table :docsmith_versions do |t|
      t.references :document,       null: false, foreign_key: { to_table: :docsmith_documents }
      t.integer    :version_number, null: false
      t.text       :content,        null: false
      t.string     :content_type,   null: false
      t.string     :author_type
      t.bigint     :author_id
      t.string     :change_summary
      t.jsonb      :metadata,       null: false, default: {}
      t.datetime   :created_at,     null: false
    end
    add_index :docsmith_versions, %i[document_id version_number], unique: true
    add_index :docsmith_versions, %i[author_type author_id]

    create_table :docsmith_version_tags do |t|
      t.references :document,   null: false, foreign_key: { to_table: :docsmith_documents }
      t.bigint     :version_id, null: false
      t.string     :name,       null: false
      t.string     :author_type
      t.bigint     :author_id
      t.datetime   :created_at, null: false
    end
    add_index :docsmith_version_tags, %i[document_id name], unique: true
    add_index :docsmith_version_tags, [:version_id]
    add_foreign_key :docsmith_version_tags, :docsmith_versions, column: :version_id
  end
end
```

- [ ] **Step 3: Create initializer template**

```erb
<%# lib/generators/docsmith/install/templates/docsmith_initializer.rb.erb %>
# frozen_string_literal: true

Docsmith.configure do |config|
  # Resolution order: per-class docsmith_config > this global config > gem defaults
  #
  # config.default_content_field    = :body          # gem default: :body
  # config.default_content_type     = :markdown      # gem default: :markdown (:html, :markdown, :json)
  # config.auto_save                = true           # gem default: true
  # config.default_debounce         = 30             # gem default: 30 (integer seconds)
  # config.max_versions             = nil            # gem default: nil (unlimited)
  # config.content_extractor        = nil            # example: ->(record) { record.body.to_html }
  # config.table_prefix             = "docsmith"     # gem default: "docsmith"
  # config.diff_context_lines       = 3              # used in Phase 2
  #
  # Event hooks (fires synchronously before AS::Notifications):
  # config.on(:version_created)  { |event| Rails.logger.info "v#{event.version.version_number} saved" }
  # config.on(:version_restored) { |event| }
  # config.on(:version_tagged)   { |event| }
end
```

- [ ] **Step 4: Commit**

```bash
git add lib/generators/
git commit -m "feat(generator): add rails generate docsmith:install with migration and initializer templates

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 1.23 — Phase 1 integration test

**Files:**
- Create: `spec/docsmith/phase1_integration_spec.rb`

- [ ] **Step 1: Write the integration test**

```ruby
# spec/docsmith/phase1_integration_spec.rb
# frozen_string_literal: true

RSpec.describe "Phase 1 integration — core versioning" do
  let(:user)    { create(:user) }
  let(:article) { create(:article, body: "# Introduction\n\nFirst draft.") }

  it "full versioning lifecycle" do
    # 1. First save_version! creates v1
    v1 = article.save_version!(author: user, summary: "Initial draft")
    expect(v1.version_number).to eq(1)
    expect(v1.content).to eq("# Introduction\n\nFirst draft.")
    expect(v1.author).to eq(user)
    expect(article.versions.count).to eq(1)

    # 2. Identical content returns nil
    expect(article.save_version!(author: user)).to be_nil

    # 3. Second version after content change
    article.update_columns(body: "# Introduction\n\nSecond draft.")
    article.instance_variable_set(:@_docsmith_document, nil)
    article.send(:_docsmith_document).update_column(:content, "# Introduction\n\nSecond draft.")
    v2 = article.save_version!(author: user, summary: "Second draft")
    expect(v2.version_number).to eq(2)
    expect(article.versions.count).to eq(2)

    # 4. current_version returns v2
    expect(article.current_version.version_number).to eq(2)

    # 5. version(1) returns v1
    expect(article.version(1).content).to eq("# Introduction\n\nFirst draft.")

    # 6. Restore creates v3 with v1 content
    v3 = article.restore_version!(1, author: user)
    expect(v3.version_number).to eq(3)
    expect(v3.content).to eq("# Introduction\n\nFirst draft.")
    expect(article.reload.body).to eq("# Introduction\n\nFirst draft.")

    # 7. Tagging
    article.tag_version!(1, name: "v1.0-release", author: user)
    expect(article.tagged_version("v1.0-release").version_number).to eq(1)
    expect(article.version_tags(1)).to include("v1.0-release")

    # 8. Duplicate tag raises
    expect { article.tag_version!(1, name: "v1.0-release", author: user) }
      .to raise_error(Docsmith::TagAlreadyExists)

    # 9. Events fire
    fired = []
    Docsmith.configure { |c| c.on(:version_created) { |e| fired << e.version.version_number } }
    article.update_columns(body: "v4 content")
    article.send(:_docsmith_document).update_column(:content, "v4 content")
    article.save_version!(author: user)
    expect(fired).to include(4)
  end

  it "auto_save_version! respects debounce" do
    article.auto_save_version!(author: user)
    expect(article.versions.count).to eq(1)

    # Within debounce — no new version
    result = article.auto_save_version!(author: user)
    expect(result).to be_nil
    expect(article.versions.count).to eq(1)
  end

  it "standalone Docsmith::Document API" do
    doc = Docsmith::Document.create!(
      title: "Spec", content: "# Hello", content_type: "markdown"
    )
    v1 = Docsmith::VersionManager.save!(doc, author: user, summary: "Initial")
    expect(v1.version_number).to eq(1)

    doc.update_column(:content, "# Hello updated")
    v2 = Docsmith::VersionManager.save!(doc, author: user)
    expect(v2.version_number).to eq(2)

    Docsmith::VersionManager.restore!(doc, version: 1, author: user)
    expect(doc.reload.content).to eq("# Hello")

    Docsmith::VersionManager.tag!(doc, version: 1, name: "v1.0", author: user)
    expect(Docsmith::VersionTag.find_by(name: "v1.0")).not_to be_nil
  end

  it "config precedence: per-class > global > defaults" do
    Docsmith.configure { |c| c.default_debounce = 60 }
    # Article sets content_type: :markdown but not debounce → uses global 60
    config = Article.docsmith_resolved_config
    expect(config[:debounce]).to eq(60)
    expect(config[:content_type]).to eq(:markdown) # per-class wins
  end
end
```

- [ ] **Step 2: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/phase1_integration_spec.rb
```

Expected: `4 examples, 0 failures`

- [ ] **Step 3: Run the full Phase 1 suite**

```bash
bundle exec rspec spec/
```

Expected: all examples pass, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add spec/docsmith/phase1_integration_spec.rb
git commit -m "test(integration): add Phase 1 end-to-end integration spec

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

**Phase 1 complete.** All 23 tasks implemented and tested.
Run `bundle exec rspec spec/` to confirm green before proceeding to Phase 2.

---

## File Map — Phase 2

| File | Action | Responsibility |
|---|---|---|
| `lib/docsmith/diff/renderers/base.rb` | Create | Line-level diff computation + HTML rendering via diff-lcs |
| `lib/docsmith/diff/renderers/registry.rb` | Create | Renderer registration by content type |
| `lib/docsmith/diff/result.rb` | Create | Diff result object (stats, changes, to_html, to_json) |
| `lib/docsmith/diff/engine.rb` | Create | `Docsmith::Diff.between` entry point |
| `lib/docsmith/rendering/html_renderer.rb` | Create | Renders document content (not diff) as HTML |
| `lib/docsmith/rendering/json_renderer.rb` | Create | Renders document content as JSON |
| `lib/docsmith/document_version.rb` | Modify | Add `render(format)` method |
| `lib/docsmith/versionable.rb` | Modify | Add `diff_from`, `diff_between` |
| `lib/docsmith.rb` | Modify | Require Phase 2 files |
| `spec/docsmith/diff/renderers/base_renderer_spec.rb` | Create | Base renderer + Registry unit specs |
| `spec/docsmith/diff/result_spec.rb` | Create | Result object specs |
| `spec/docsmith/diff/engine_spec.rb` | Create | Engine integration specs |
| `spec/docsmith/rendering/html_renderer_spec.rb` | Create | HtmlRenderer specs |
| `spec/docsmith/rendering/json_renderer_spec.rb` | Create | JsonRenderer specs |
| `spec/docsmith/phase2_integration_spec.rb` | Create | End-to-end Phase 2 test |

---

## Phase 2: Diff & Rendering

### Task 2.1 — `Diff::Renderers::Base` (line-level diff via diff-lcs)

**Files:**
- Create: `lib/docsmith/diff/renderers/base.rb`
- Create: `spec/docsmith/diff/renderers/base_renderer_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/diff/renderers/base_renderer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Diff::Renderers::Base do
  subject(:renderer) { described_class.new }

  describe "#compute" do
    it "detects added lines" do
      changes = renderer.compute("line one\nline two", "line one\nline two\nline three")
      expect(changes).to include(a_hash_including(type: :addition, content: "line three"))
    end

    it "detects deleted lines" do
      changes = renderer.compute("line one\nline two", "line one")
      expect(changes).to include(a_hash_including(type: :deletion, content: "line two"))
    end

    it "detects modified lines" do
      changes = renderer.compute("hello world", "hello ruby")
      expect(changes).to include(a_hash_including(type: :modification, old_content: "hello world", new_content: "hello ruby"))
    end

    it "returns empty array for identical content" do
      expect(renderer.compute("same", "same")).to be_empty
    end

    it "includes 1-indexed line numbers" do
      changes = renderer.compute("a\nb", "a\nc")
      mod = changes.find { |c| c[:type] == :modification }
      expect(mod[:line]).to eq(2)
    end
  end

  describe "#render_html" do
    it "wraps additions in <ins> tags with docsmith-addition class" do
      changes = [{ type: :addition, line: 1, content: "new line" }]
      expect(renderer.render_html(changes)).to include('<ins class="docsmith-addition">new line</ins>')
    end

    it "wraps deletions in <del> tags with docsmith-deletion class" do
      changes = [{ type: :deletion, line: 1, content: "old line" }]
      expect(renderer.render_html(changes)).to include('<del class="docsmith-deletion">old line</del>')
    end

    it "escapes HTML special characters in content" do
      changes = [{ type: :addition, line: 1, content: "<script>alert('xss')</script>" }]
      html = renderer.render_html(changes)
      expect(html).not_to include("<script>")
      expect(html).to include("&lt;script&gt;")
    end

    it "wraps output in a docsmith-diff div" do
      expect(renderer.render_html([])).to start_with('<div class="docsmith-diff">')
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/diff/renderers/base_renderer_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Diff::Renderers::Base`

- [ ] **Step 3: Create directory and implement**

```bash
mkdir -p lib/docsmith/diff/renderers spec/docsmith/diff/renderers
```

```ruby
# lib/docsmith/diff/renderers/base.rb
# frozen_string_literal: true

require "diff/lcs"
require "cgi"

module Docsmith
  module Diff
    module Renderers
      # Line-level diff renderer using diff-lcs.
      # Handles all content types (markdown, html, json) for Phase 2.
      # Register content-type-specific renderers via Renderers::Registry when needed.
      class Base
        # Computes line-level changes between two content strings.
        #
        # @param old_content [String]
        # @param new_content [String]
        # @return [Array<Hash>] change hashes with :type, :line, and content fields
        def compute(old_content, new_content)
          old_lines = old_content.split("\n", -1)
          new_lines = new_content.split("\n", -1)
          changes   = []

          ::Diff::LCS.sdiff(old_lines, new_lines).each do |hunk|
            case hunk.action
            when "+"
              changes << { type: :addition, line: hunk.new_position + 1, content: hunk.new_element.to_s }
            when "-"
              changes << { type: :deletion, line: hunk.old_position + 1, content: hunk.old_element.to_s }
            when "!"
              changes << {
                type:        :modification,
                line:        hunk.old_position + 1,
                old_content: hunk.old_element.to_s,
                new_content: hunk.new_element.to_s
              }
            end
          end

          changes
        end

        # Renders a change array as an HTML diff representation.
        #
        # @param changes [Array<Hash>]
        # @return [String] HTML string
        def render_html(changes)
          lines = changes.map do |change|
            case change[:type]
            when :addition
              %(<ins class="docsmith-addition">#{CGI.escapeHTML(change[:content])}</ins>)
            when :deletion
              %(<del class="docsmith-deletion">#{CGI.escapeHTML(change[:content])}</del>)
            when :modification
              %(<del class="docsmith-deletion">#{CGI.escapeHTML(change[:old_content])}</del>) \
                %(<ins class="docsmith-addition">#{CGI.escapeHTML(change[:new_content])}</ins>)
            end
          end
          %(<div class="docsmith-diff">#{lines.join("\n")}</div>)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/diff/renderers/base_renderer_spec.rb
```

Expected: `8 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/diff/renderers/base.rb spec/docsmith/diff/renderers/base_renderer_spec.rb
git commit -m "feat(diff): add Diff::Renderers::Base with line-level diff-lcs computation

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 2.2 — `Diff::Renderers::Registry`

**Files:**
- Create: `lib/docsmith/diff/renderers/registry.rb`
- Test: append to `spec/docsmith/diff/renderers/base_renderer_spec.rb`

- [ ] **Step 1: Write the failing test** (append to `base_renderer_spec.rb`)

```ruby
# Append to spec/docsmith/diff/renderers/base_renderer_spec.rb

RSpec.describe Docsmith::Diff::Renderers::Registry do
  after { described_class.reset! }

  describe ".for" do
    it "returns Base for unregistered content types" do
      expect(described_class.for("markdown")).to eq(Docsmith::Diff::Renderers::Base)
    end

    it "returns the registered renderer for a registered type" do
      custom = Class.new(Docsmith::Diff::Renderers::Base)
      described_class.register("html", custom)
      expect(described_class.for("html")).to eq(custom)
    end

    it "accepts symbol content types" do
      custom = Class.new(Docsmith::Diff::Renderers::Base)
      described_class.register(:json, custom)
      expect(described_class.for("json")).to eq(custom)
    end
  end

  describe ".register" do
    it "adds a renderer to the registry" do
      custom = Class.new(Docsmith::Diff::Renderers::Base)
      described_class.register("custom", custom)
      expect(described_class.all).to include("custom" => custom)
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/diff/renderers/base_renderer_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Diff::Renderers::Registry`

- [ ] **Step 3: Implement**

```ruby
# lib/docsmith/diff/renderers/registry.rb
# frozen_string_literal: true

module Docsmith
  module Diff
    module Renderers
      # Registry for diff renderers keyed by content type string.
      # Falls back to Base for unregistered types.
      # Use Docsmith.configure { |c| c.register_diff_renderer(:html, MyRenderer) }
      # to add custom renderers at runtime.
      class Registry
        @renderers = {}

        class << self
          # @param content_type [String, Symbol]
          # @param renderer_class [Class]
          # @return [void]
          def register(content_type, renderer_class)
            @renderers[content_type.to_s] = renderer_class
          end

          # @param content_type [String, Symbol]
          # @return [Class] renderer class; defaults to Base for unregistered types
          def for(content_type)
            @renderers.fetch(content_type.to_s, Base)
          end

          # @return [Hash] copy of registered renderers
          def all
            @renderers.dup
          end

          # Resets registry to empty — for test isolation only.
          # @return [void]
          def reset!
            @renderers = {}
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/diff/renderers/base_renderer_spec.rb
```

Expected: `12 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/diff/renderers/registry.rb spec/docsmith/diff/renderers/base_renderer_spec.rb
git commit -m "feat(diff): add Diff::Renderers::Registry for custom renderer registration

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 2.3 — `Diff::Result`

**Files:**
- Create: `lib/docsmith/diff/result.rb`
- Create: `spec/docsmith/diff/result_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/diff/result_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Diff::Result do
  let(:changes) do
    [
      { type: :addition,     line: 3, content: "new line" },
      { type: :deletion,     line: 1, content: "old line" },
      { type: :modification, line: 2, old_content: "before", new_content: "after" }
    ]
  end

  subject(:result) do
    described_class.new(
      content_type: "markdown",
      from_version: 1,
      to_version:   3,
      changes:      changes
    )
  end

  it "exposes content_type, from_version, to_version, changes" do
    expect(result.content_type).to eq("markdown")
    expect(result.from_version).to eq(1)
    expect(result.to_version).to eq(3)
    expect(result.changes).to eq(changes)
  end

  describe "#additions" do
    it "counts addition-type changes only" do
      expect(result.additions).to eq(1)
    end
  end

  describe "#deletions" do
    it "counts deletion-type changes only" do
      expect(result.deletions).to eq(1)
    end
  end

  describe "#to_html" do
    it "returns HTML string with diff markup" do
      html = result.to_html
      expect(html).to include("docsmith-diff")
      expect(html).to include("docsmith-addition")
      expect(html).to include("docsmith-deletion")
    end
  end

  describe "#to_json" do
    it "returns valid JSON" do
      expect { JSON.parse(result.to_json) }.not_to raise_error
    end

    it "includes stats block with additions and deletions" do
      parsed = JSON.parse(result.to_json)
      expect(parsed["stats"]).to eq("additions" => 1, "deletions" => 1)
    end

    it "includes content_type, from_version, to_version" do
      parsed = JSON.parse(result.to_json)
      expect(parsed["content_type"]).to eq("markdown")
      expect(parsed["from_version"]).to eq(1)
      expect(parsed["to_version"]).to eq(3)
    end

    it "serializes addition changes with position and content" do
      parsed = JSON.parse(result.to_json)
      addition = parsed["changes"].find { |c| c["type"] == "addition" }
      expect(addition).to include("position" => { "line" => 3 }, "content" => "new line")
    end

    it "serializes modification changes with old_content and new_content" do
      parsed = JSON.parse(result.to_json)
      mod = parsed["changes"].find { |c| c["type"] == "modification" }
      expect(mod).to include("old_content" => "before", "new_content" => "after")
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/diff/result_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Diff::Result`

- [ ] **Step 3: Create the directory and implement**

```bash
mkdir -p lib/docsmith/diff spec/docsmith/diff
```

```ruby
# lib/docsmith/diff/result.rb
# frozen_string_literal: true

require "json"

module Docsmith
  module Diff
    # Holds the computed diff between two DocumentVersion records.
    # Produced by Diff::Engine.between; consumed by callers for stats and rendering.
    class Result
      # @return [String] content type of the diffed document ("markdown", "html", "json")
      attr_reader :content_type
      # @return [Integer] version_number of the from (older) version
      attr_reader :from_version
      # @return [Integer] version_number of the to (newer) version
      attr_reader :to_version
      # @return [Array<Hash>] change hashes produced by Renderers::Base#compute
      attr_reader :changes

      # @param content_type [String]
      # @param from_version [Integer]
      # @param to_version [Integer]
      # @param changes [Array<Hash>]
      def initialize(content_type:, from_version:, to_version:, changes:)
        @content_type = content_type
        @from_version = from_version
        @to_version   = to_version
        @changes      = changes
      end

      # @return [Integer] number of added lines
      def additions
        changes.count { |c| c[:type] == :addition }
      end

      # @return [Integer] number of deleted lines
      def deletions
        changes.count { |c| c[:type] == :deletion }
      end

      # @return [String] HTML diff representation
      def to_html
        Renderers::Registry.for(content_type).new.render_html(changes)
      end

      # @return [String] JSON diff representation matching the documented schema
      def to_json(*)
        {
          content_type: content_type,
          from_version: from_version,
          to_version:   to_version,
          stats:        { additions: additions, deletions: deletions },
          changes:      changes.map { |c| serialize_change(c) }
        }.to_json
      end

      private

      def serialize_change(change)
        case change[:type]
        when :addition
          { type: "addition", position: { line: change[:line] }, content: change[:content] }
        when :deletion
          { type: "deletion", position: { line: change[:line] }, content: change[:content] }
        when :modification
          {
            type:        "modification",
            position:    { line: change[:line] },
            old_content: change[:old_content],
            new_content: change[:new_content]
          }
        else
          change.transform_keys(&:to_s)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/diff/result_spec.rb
```

Expected: `9 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/diff/result.rb spec/docsmith/diff/result_spec.rb
git commit -m "feat(diff): add Diff::Result with stats and to_html/to_json rendering

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 2.4 — `Diff::Engine` + `Docsmith::Diff.between`

**Files:**
- Create: `lib/docsmith/diff/engine.rb`
- Create: `spec/docsmith/diff/engine_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/diff/engine_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Diff::Engine do
  include FactoryBot::Syntax::Methods

  let(:doc) { create(:document, content: "line one\nline two", content_type: "markdown") }
  let(:v1)  { create(:document_version, document: doc, content: "line one\nline two", version_number: 1, content_type: "markdown") }
  let(:v2)  { create(:document_version, document: doc, content: "line one\nline two\nline three", version_number: 2, content_type: "markdown") }

  describe ".between" do
    subject(:result) { described_class.between(v1, v2) }

    it "returns a Diff::Result" do
      expect(result).to be_a(Docsmith::Diff::Result)
    end

    it "sets content_type from the from-version" do
      expect(result.content_type).to eq("markdown")
    end

    it "sets from_version and to_version from the version numbers" do
      expect(result.from_version).to eq(1)
      expect(result.to_version).to eq(2)
    end

    it "detects the added line" do
      expect(result.additions).to eq(1)
      expect(result.deletions).to eq(0)
    end
  end

  describe "Docsmith::Diff.between (module convenience method)" do
    it "delegates to Engine.between and returns a Result" do
      result = Docsmith::Diff.between(v1, v2)
      expect(result).to be_a(Docsmith::Diff::Result)
      expect(result.additions).to eq(1)
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/diff/engine_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Diff::Engine`

- [ ] **Step 3: Implement**

```ruby
# lib/docsmith/diff/engine.rb
# frozen_string_literal: true

module Docsmith
  module Diff
    # Computes diffs between two DocumentVersion records.
    # Uses Renderers::Registry to select the renderer for the content type.
    class Engine
      class << self
        # @param version_a [Docsmith::DocumentVersion] the older version
        # @param version_b [Docsmith::DocumentVersion] the newer version
        # @return [Docsmith::Diff::Result]
        def between(version_a, version_b)
          content_type = version_a.content_type.to_s
          renderer     = Renderers::Registry.for(content_type).new
          changes      = renderer.compute(version_a.content.to_s, version_b.content.to_s)

          Result.new(
            content_type: content_type,
            from_version: version_a.version_number,
            to_version:   version_b.version_number,
            changes:      changes
          )
        end
      end
    end

    # Convenience module method: Docsmith::Diff.between(v1, v2)
    def self.between(version_a, version_b)
      Engine.between(version_a, version_b)
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/diff/engine_spec.rb
```

Expected: `6 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/diff/engine.rb spec/docsmith/diff/engine_spec.rb
git commit -m "feat(diff): add Diff::Engine and Docsmith::Diff.between entry point

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 2.5 — `Rendering::HtmlRenderer` + `Rendering::JsonRenderer`

**Files:**
- Create: `lib/docsmith/rendering/html_renderer.rb`
- Create: `lib/docsmith/rendering/json_renderer.rb`
- Create: `spec/docsmith/rendering/html_renderer_spec.rb`
- Create: `spec/docsmith/rendering/json_renderer_spec.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/docsmith/rendering/html_renderer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Rendering::HtmlRenderer do
  subject(:renderer) { described_class.new }

  def stub_version(content:, content_type:)
    double("version", content: content, content_type: content_type)
  end

  describe "#render" do
    context "with html content_type" do
      it "returns the content as-is" do
        expect(renderer.render(stub_version(content: "<p>Hello</p>", content_type: "html"))).to eq("<p>Hello</p>")
      end
    end

    context "with markdown content_type" do
      it "wraps content in a pre tag with docsmith-markdown class" do
        html = renderer.render(stub_version(content: "# Hello\nWorld", content_type: "markdown"))
        expect(html).to include("docsmith-markdown")
        expect(html).to include("# Hello")
      end
    end

    context "with json content_type" do
      it "pretty-prints JSON in a pre tag with docsmith-json class" do
        html = renderer.render(stub_version(content: '{"key":"value"}', content_type: "json"))
        expect(html).to include("docsmith-json")
        expect(html).to include('"key"')
      end
    end

    context "with invalid JSON and json content_type" do
      it "falls back gracefully without raising" do
        expect { renderer.render(stub_version(content: "not-json", content_type: "json")) }.not_to raise_error
      end
    end
  end
end
```

```ruby
# spec/docsmith/rendering/json_renderer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Rendering::JsonRenderer do
  subject(:renderer) { described_class.new }

  def stub_version(content:, content_type:)
    double("version", content: content, content_type: content_type)
  end

  describe "#render" do
    context "with json content_type" do
      it "returns pretty-printed JSON" do
        result = renderer.render(stub_version(content: '{"key":"value"}', content_type: "json"))
        parsed = JSON.parse(result)
        expect(parsed["key"]).to eq("value")
      end
    end

    context "with non-json content_type" do
      it "wraps content in a JSON envelope with content_type and content keys" do
        result = renderer.render(stub_version(content: "# Markdown", content_type: "markdown"))
        parsed = JSON.parse(result)
        expect(parsed["content_type"]).to eq("markdown")
        expect(parsed["content"]).to eq("# Markdown")
      end
    end

    context "with invalid JSON content and json content_type" do
      it "returns an error envelope without raising" do
        result = renderer.render(stub_version(content: "broken", content_type: "json"))
        parsed = JSON.parse(result)
        expect(parsed["error"]).to eq("invalid_json")
      end
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/rendering/html_renderer_spec.rb spec/docsmith/rendering/json_renderer_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Rendering`

- [ ] **Step 3: Create directories and implement**

```bash
mkdir -p lib/docsmith/rendering spec/docsmith/rendering
```

```ruby
# lib/docsmith/rendering/html_renderer.rb
# frozen_string_literal: true

require "cgi"
require "json"

module Docsmith
  module Rendering
    # Renders a DocumentVersion's content as an HTML string.
    # Markdown is shown pre-formatted (no external gem dependency).
    # JSON is pretty-printed inside a pre block.
    # Subclass and override #render to plug in a markdown gem (e.g. redcarpet).
    class HtmlRenderer
      # @param version [Docsmith::DocumentVersion]
      # @param options [Hash] unused in Phase 2; available for subclasses
      # @return [String] HTML representation of the version content
      def render(version, **options)
        content      = version.content.to_s
        content_type = version.content_type.to_s

        case content_type
        when "html"
          content
        when "markdown"
          "<pre class=\"docsmith-markdown\">#{CGI.escapeHTML(content)}</pre>"
        when "json"
          pretty = JSON.pretty_generate(JSON.parse(content))
          "<pre class=\"docsmith-json\">#{CGI.escapeHTML(pretty)}</pre>"
        else
          "<pre>#{CGI.escapeHTML(content)}</pre>"
        end
      rescue JSON::ParserError
        "<pre>#{CGI.escapeHTML(content)}</pre>"
      end
    end
  end
end
```

```ruby
# lib/docsmith/rendering/json_renderer.rb
# frozen_string_literal: true

require "json"

module Docsmith
  module Rendering
    # Renders a DocumentVersion's content as a JSON string.
    # For json content_type: re-parses and pretty-prints.
    # For other types: wraps content in a JSON envelope.
    class JsonRenderer
      # @param version [Docsmith::DocumentVersion]
      # @param options [Hash] unused in Phase 2
      # @return [String] JSON representation of the version content
      def render(version, **options)
        content      = version.content.to_s
        content_type = version.content_type.to_s

        case content_type
        when "json"
          JSON.pretty_generate(JSON.parse(content))
        else
          { content_type: content_type, content: content }.to_json
        end
      rescue JSON::ParserError
        { content_type: content_type, content: content, error: "invalid_json" }.to_json
      end
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/rendering/html_renderer_spec.rb spec/docsmith/rendering/json_renderer_spec.rb
```

Expected: `7 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/rendering/html_renderer.rb lib/docsmith/rendering/json_renderer.rb \
        spec/docsmith/rendering/html_renderer_spec.rb spec/docsmith/rendering/json_renderer_spec.rb
git commit -m "feat(rendering): add HtmlRenderer and JsonRenderer for document content

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 2.6 — `DocumentVersion#render`

**Files:**
- Modify: `lib/docsmith/document_version.rb`
- Test: append to `spec/docsmith/document_version_spec.rb`

- [ ] **Step 1: Write the failing test** (append inside the existing `RSpec.describe Docsmith::DocumentVersion` block)

```ruby
describe "#render" do
  include FactoryBot::Syntax::Methods

  let(:doc)     { create(:document, content: "# Hello", content_type: "markdown") }
  let(:version) { create(:document_version, document: doc, content: "# Hello", content_type: "markdown", version_number: 1) }

  it "renders :html format" do
    html = version.render(:html)
    expect(html).to include("docsmith-markdown")
    expect(html).to include("# Hello")
  end

  it "renders :json format and wraps in envelope" do
    parsed = JSON.parse(version.render(:json))
    expect(parsed["content"]).to eq("# Hello")
  end

  it "raises ArgumentError for unknown format" do
    expect { version.render(:pdf) }.to raise_error(ArgumentError, /pdf/)
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/document_version_spec.rb
```

Expected: `NoMethodError: undefined method 'render'`

- [ ] **Step 3: Add `render` to DocumentVersion** (inside the class body, after existing methods)

```ruby
# Renders this version's content in the given output format.
#
# @param format [Symbol] :html or :json
# @param options [Hash] passed through to the renderer
# @return [String]
# @raise [ArgumentError] for unknown formats
def render(format, **options)
  case format.to_sym
  when :html then Rendering::HtmlRenderer.new.render(self, **options)
  when :json then Rendering::JsonRenderer.new.render(self, **options)
  else raise ArgumentError, "Unknown render format: #{format}. Supported: :html, :json"
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/document_version_spec.rb
```

Expected: all examples pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/document_version.rb spec/docsmith/document_version_spec.rb
git commit -m "feat(rendering): add DocumentVersion#render(:html/:json)

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 2.7 — `Versionable#diff_from` + `#diff_between`

**Files:**
- Modify: `lib/docsmith/versionable.rb`
- Test: append to `spec/docsmith/versionable_spec.rb`

- [ ] **Step 1: Write the failing tests** (append inside the existing `RSpec.describe Docsmith::Versionable` block)

```ruby
describe "#diff_from" do
  include FactoryBot::Syntax::Methods

  let(:article) { create(:article, body: "line one\nline two") }
  let(:user)    { create(:user) }

  before do
    article.save_version!(author: user)
    article.body = "line one\nline two\nline three"
    article.save!
    article.save_version!(author: user)
  end

  it "returns a Diff::Result comparing version N to current" do
    result = article.diff_from(1)
    expect(result).to be_a(Docsmith::Diff::Result)
    expect(result.from_version).to eq(1)
    expect(result.additions).to eq(1)
  end

  it "raises ActiveRecord::RecordNotFound for a non-existent version" do
    expect { article.diff_from(99) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end

describe "#diff_between" do
  include FactoryBot::Syntax::Methods

  let(:article) { create(:article, body: "v1 content") }
  let(:user)    { create(:user) }

  before do
    article.save_version!(author: user)
    article.body = "v2 content"
    article.save!
    article.save_version!(author: user)
    article.body = "v3 content"
    article.save!
    article.save_version!(author: user)
  end

  it "returns a Diff::Result comparing two named versions" do
    result = article.diff_between(1, 3)
    expect(result).to be_a(Docsmith::Diff::Result)
    expect(result.from_version).to eq(1)
    expect(result.to_version).to eq(3)
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb
```

Expected: `NoMethodError: undefined method 'diff_from'`

- [ ] **Step 3: Add methods to Versionable** (inside the public instance methods section)

```ruby
# Computes a diff from version N to the current (latest) version.
#
# @param version_number [Integer]
# @return [Docsmith::Diff::Result]
# @raise [ActiveRecord::RecordNotFound] if version_number does not exist
def diff_from(version_number)
  doc    = _docsmith_document
  v_from = Docsmith::DocumentVersion.find_by!(document: doc, version_number: version_number)
  v_to   = doc.versions.order(version_number: :desc).first!
  Docsmith::Diff.between(v_from, v_to)
end

# Computes a diff between two named versions.
#
# @param from_version [Integer]
# @param to_version [Integer]
# @return [Docsmith::Diff::Result]
# @raise [ActiveRecord::RecordNotFound] if either version does not exist
def diff_between(from_version, to_version)
  doc    = _docsmith_document
  v_from = Docsmith::DocumentVersion.find_by!(document: doc, version_number: from_version)
  v_to   = Docsmith::DocumentVersion.find_by!(document: doc, version_number: to_version)
  Docsmith::Diff.between(v_from, v_to)
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb
```

Expected: all examples pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/versionable.rb spec/docsmith/versionable_spec.rb
git commit -m "feat(diff): add Versionable#diff_from and #diff_between

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 2.8 — Wire Phase 2 requires + integration test

**Files:**
- Modify: `lib/docsmith.rb`
- Create: `spec/docsmith/phase2_integration_spec.rb`

- [ ] **Step 1: Add Phase 2 requires to `lib/docsmith.rb`** (after existing Phase 1 requires)

```ruby
require_relative "docsmith/diff/renderers/base"
require_relative "docsmith/diff/renderers/registry"
require_relative "docsmith/diff/result"
require_relative "docsmith/diff/engine"
require_relative "docsmith/rendering/html_renderer"
require_relative "docsmith/rendering/json_renderer"
```

- [ ] **Step 2: Write the failing integration test**

```ruby
# spec/docsmith/phase2_integration_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Phase 2: Diff & Rendering integration" do
  include FactoryBot::Syntax::Methods

  let(:user)    { create(:user) }
  let(:article) { create(:article, body: "line one\nline two") }

  before do
    article.save_version!(author: user)
    article.body = "line one\nline two\nline three"
    article.save!
    article.save_version!(author: user)
  end

  it "diff_from returns correct addition count" do
    result = article.diff_from(1)
    expect(result.additions).to eq(1)
    expect(result.deletions).to eq(0)
  end

  it "diff_between returns a Result with correct from/to version numbers" do
    result = article.diff_between(1, 2)
    expect(result.from_version).to eq(1)
    expect(result.to_version).to eq(2)
  end

  it "Diff::Result#to_html includes diff markup" do
    result = article.diff_between(1, 2)
    expect(result.to_html).to include("docsmith-addition")
  end

  it "Diff::Result#to_json returns valid JSON with stats" do
    result = article.diff_between(1, 2)
    parsed = JSON.parse(result.to_json)
    expect(parsed["stats"]["additions"]).to eq(1)
  end

  it "DocumentVersion#render(:html) returns content" do
    version = article.version(1)
    html = version.render(:html)
    expect(html).to include("line one")
  end

  it "DocumentVersion#render(:json) returns a JSON envelope" do
    version = article.version(1)
    parsed = JSON.parse(version.render(:json))
    expect(parsed["content"]).to include("line one")
  end
end
```

- [ ] **Step 3: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/phase2_integration_spec.rb
```

Expected: `6 examples, 0 failures`

- [ ] **Step 4: Run the full Phase 1+2 suite**

```bash
bundle exec rspec spec/
```

Expected: all examples pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith.rb spec/docsmith/phase2_integration_spec.rb
git commit -m "feat(diff): wire Phase 2 requires and add integration test

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

**Phase 2 complete.** 8 tasks implemented and tested.
Run `bundle exec rspec spec/` to confirm green before proceeding to Phase 3.


---

## File Map — Phase 3

| File | Action | Responsibility |
|---|---|---|
| `spec/support/schema.rb` | Modify | Add `docsmith_comments` table |
| `lib/generators/docsmith/install/templates/create_docsmith_tables.rb.erb` | Modify | Add `docsmith_comments` migration block |
| `lib/docsmith/events/event.rb` | Modify | Add `comment` field to Event struct |
| `lib/docsmith/document.rb` | Modify | Add `belongs_to :subject, polymorphic: true` if not already present |
| `lib/docsmith/document_version.rb` | Modify | Add `has_many :comments` association |
| `lib/docsmith/comments/comment.rb` | Create | `Docsmith::Comments::Comment` AR model |
| `lib/docsmith/comments/anchor.rb` | Create | Range anchor build + migrate logic |
| `lib/docsmith/comments/manager.rb` | Create | `add!` and `resolve!` service methods |
| `lib/docsmith/comments/migrator.rb` | Create | Cross-version comment migration |
| `lib/docsmith/versionable.rb` | Modify | Add comment query and mutation methods |
| `lib/docsmith.rb` | Modify | Require Phase 3 files |
| `spec/docsmith/comments/comment_spec.rb` | Create | Comment model specs |
| `spec/docsmith/comments/anchor_spec.rb` | Create | Anchor build/migrate specs |
| `spec/docsmith/comments/manager_spec.rb` | Create | Manager service specs |
| `spec/docsmith/comments/migrator_spec.rb` | Create | Migrator specs |
| `spec/docsmith/phase3_integration_spec.rb` | Create | End-to-end Phase 3 test |

---

## Phase 3: Comments & Inline Annotations

### Task 3.1 — Schema + Event struct update

**Files:**
- Modify: `spec/support/schema.rb`
- Modify: `lib/generators/docsmith/install/templates/create_docsmith_tables.rb.erb`
- Modify: `lib/docsmith/events/event.rb`
- Modify: `lib/docsmith/document.rb`
- Modify: `lib/docsmith/document_version.rb`

- [ ] **Step 1: Add `docsmith_comments` table to test schema**

Append inside the `ActiveRecord::Schema.define` block in `spec/support/schema.rb`:

```ruby
create_table :docsmith_comments, force: true do |t|
  t.bigint   :version_id,        null: false
  t.bigint   :parent_id
  t.string   :author_type
  t.bigint   :author_id
  t.text     :body,              null: false
  t.string   :anchor_type,       null: false, default: "document"
  t.text     :anchor_data,       null: false, default: "{}"
  t.boolean  :resolved,          null: false, default: false
  t.string   :resolved_by_type
  t.bigint   :resolved_by_id
  t.datetime :resolved_at
  t.datetime :created_at,        null: false
  t.datetime :updated_at,        null: false
end

add_index :docsmith_comments, :version_id
add_index :docsmith_comments, :parent_id
add_index :docsmith_comments, [:author_type, :author_id]
```

- [ ] **Step 2: Add migration block to generator template**

Append inside the `change` method in `lib/generators/docsmith/install/templates/create_docsmith_tables.rb.erb`:

```ruby
create_table :docsmith_comments do |t|
  t.bigint   :version_id,        null: false
  t.bigint   :parent_id
  t.string   :author_type
  t.bigint   :author_id
  t.text     :body,              null: false
  t.string   :anchor_type,       null: false, default: "document"
  t.text     :anchor_data,       null: false, default: "{}"
  t.boolean  :resolved,          null: false, default: false
  t.string   :resolved_by_type
  t.bigint   :resolved_by_id
  t.datetime :resolved_at
  t.timestamps                   null: false
end

add_index :docsmith_comments, :version_id
add_index :docsmith_comments, :parent_id
add_index :docsmith_comments, [:author_type, :author_id]
add_foreign_key :docsmith_comments, :docsmith_versions, column: :version_id
add_foreign_key :docsmith_comments, :docsmith_comments, column: :parent_id
```

- [ ] **Step 3: Add `comment` field to Event struct**

In `lib/docsmith/events/event.rb`, update the Struct definition:

```ruby
# Change from:
Docsmith::Events::Event = Struct.new(
  :name, :record, :document, :version, :author, :from_version, :tag_name,
  keyword_init: true
)

# Change to:
Docsmith::Events::Event = Struct.new(
  :name, :record, :document, :version, :author, :from_version, :tag_name, :comment,
  keyword_init: true
)
```

- [ ] **Step 4: Add polymorphic subject association to Document** (skip if already present)

In `lib/docsmith/document.rb`, add inside the class body:

```ruby
belongs_to :subject, polymorphic: true, optional: true
```

This provides `document.subject` returning the originating AR record for mixin-created documents (nil for standalone).

- [ ] **Step 5: Add comments association to DocumentVersion**

In `lib/docsmith/document_version.rb`, add inside the class body:

```ruby
has_many :comments, class_name: "Docsmith::Comments::Comment",
                    foreign_key: :version_id, dependent: :destroy
```

- [ ] **Step 6: Run the full suite — confirm no regressions**

```bash
bundle exec rspec spec/
```

Expected: all Phase 1+2 examples pass, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add spec/support/schema.rb \
        lib/generators/docsmith/install/templates/create_docsmith_tables.rb.erb \
        lib/docsmith/events/event.rb \
        lib/docsmith/document.rb \
        lib/docsmith/document_version.rb
git commit -m "feat(comments): add docsmith_comments schema, Event#comment field, and associations

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 3.2 — `Comments::Comment` AR model

**Files:**
- Create: `lib/docsmith/comments/comment.rb`
- Create: `spec/docsmith/comments/comment_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/comments/comment_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Comments::Comment do
  include FactoryBot::Syntax::Methods

  let(:user)    { create(:user) }
  let(:doc)     { create(:document, content: "hello", content_type: "markdown") }
  let(:version) { create(:document_version, document: doc, content: "hello", version_number: 1, content_type: "markdown") }

  describe "associations" do
    it "belongs to a version" do
      comment = described_class.create!(
        version: version, author: user, body: "nice",
        anchor_type: "document", anchor_data: {}
      )
      expect(comment.version).to eq(version)
    end

    it "supports threaded replies via parent/replies" do
      parent = described_class.create!(
        version: version, author: user, body: "parent",
        anchor_type: "document", anchor_data: {}
      )
      reply = described_class.create!(
        version: version, author: user, body: "reply", parent: parent,
        anchor_type: "document", anchor_data: {}
      )
      expect(reply.parent).to eq(parent)
      expect(parent.replies).to include(reply)
    end
  end

  describe "validations" do
    it "requires body" do
      comment = described_class.new(version: version, author: user, anchor_type: "document", anchor_data: {})
      expect(comment).not_to be_valid
      expect(comment.errors[:body]).not_to be_empty
    end

    it "requires anchor_type to be document or range" do
      comment = described_class.new(
        version: version, author: user, body: "text",
        anchor_type: "invalid", anchor_data: {}
      )
      expect(comment).not_to be_valid
    end
  end

  describe "scopes" do
    let!(:root1) { described_class.create!(version: version, author: user, body: "root1", anchor_type: "document", anchor_data: {}) }
    let!(:root2) { described_class.create!(version: version, author: user, body: "root2", anchor_type: "document", anchor_data: {}) }
    let!(:reply) { described_class.create!(version: version, author: user, body: "reply", anchor_type: "document", anchor_data: {}, parent: root1) }

    it ".top_level returns only root-level comments" do
      expect(described_class.top_level.to_a).to contain_exactly(root1, root2)
    end

    it ".unresolved returns only unresolved comments" do
      expect(described_class.unresolved.count).to eq(3)
    end

    it ".document_level returns only document anchor type" do
      described_class.create!(version: version, author: user, body: "range", anchor_type: "range", anchor_data: { start_offset: 0, end_offset: 1 }.to_json)
      expect(described_class.document_level.count).to eq(3)
      expect(described_class.range_anchored.count).to eq(1)
    end
  end

  describe "#anchor_data accessor" do
    it "accepts a Hash and returns a Hash" do
      comment = described_class.create!(
        version: version, author: user, body: "note",
        anchor_type: "document", anchor_data: { foo: "bar" }
      )
      expect(comment.anchor_data).to be_a(Hash)
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/comments/comment_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Comments`

- [ ] **Step 3: Create directory and implement**

```bash
mkdir -p lib/docsmith/comments spec/docsmith/comments
```

```ruby
# lib/docsmith/comments/comment.rb
# frozen_string_literal: true

require "json"

module Docsmith
  module Comments
    # Represents a comment on a specific DocumentVersion.
    # Supports document-level and range-anchored inline annotations,
    # threaded replies via parent/replies, and resolution tracking.
    class Comment < ActiveRecord::Base
      self.table_name = "docsmith_comments"

      belongs_to :version,     class_name: "Docsmith::DocumentVersion", foreign_key: :version_id
      belongs_to :author,      polymorphic: true, optional: true
      belongs_to :parent,      class_name: "Docsmith::Comments::Comment", optional: true
      belongs_to :resolved_by, polymorphic: true, optional: true
      has_many   :replies,     class_name: "Docsmith::Comments::Comment",
                               foreign_key: :parent_id, dependent: :destroy

      validates :body,        presence: true
      validates :anchor_type, inclusion: { in: %w[document range] }

      scope :top_level,      -> { where(parent_id: nil) }
      scope :unresolved,     -> { where(resolved: false) }
      scope :document_level, -> { where(anchor_type: "document") }
      scope :range_anchored, -> { where(anchor_type: "range") }

      # Deserializes anchor_data from JSON text (SQLite) or returns hash directly (PostgreSQL jsonb).
      #
      # @return [Hash]
      def anchor_data
        raw = read_attribute(:anchor_data)
        raw.is_a?(String) ? JSON.parse(raw) : raw.to_h
      end

      # Serializes anchor_data as JSON for storage.
      #
      # @param data [Hash, String]
      def anchor_data=(data)
        write_attribute(:anchor_data, data.is_a?(String) ? data : data.to_json)
      end
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/comments/comment_spec.rb
```

Expected: `10 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/comments/comment.rb spec/docsmith/comments/comment_spec.rb
git commit -m "feat(comments): add Comments::Comment AR model with scopes and threading

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 3.3 — `Comments::Anchor`

**Files:**
- Create: `lib/docsmith/comments/anchor.rb`
- Create: `spec/docsmith/comments/anchor_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/comments/anchor_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Comments::Anchor do
  let(:content) { "The quick brown fox jumps over the lazy dog" }

  describe ".build" do
    subject(:anchor) { described_class.build(content, start_offset: 4, end_offset: 9) }

    it "captures the anchored text" do
      expect(anchor[:anchored_text]).to eq("quick")
    end

    it "stores start and end offsets" do
      expect(anchor[:start_offset]).to eq(4)
      expect(anchor[:end_offset]).to eq(9)
    end

    it "sets status to active" do
      expect(anchor[:status]).to eq(Docsmith::Comments::Anchor::ACTIVE)
    end

    it "stores a SHA256 content_hash of the anchored text" do
      require "digest"
      expect(anchor[:content_hash]).to eq(Digest::SHA256.hexdigest("quick"))
    end
  end

  describe ".migrate" do
    let(:original_anchor) do
      described_class.build(content, start_offset: 4, end_offset: 9)
                     .transform_keys(&:to_s)  # simulate string-keyed JSON round-trip
    end

    context "when anchored text is at the exact same offset in the new content" do
      it "returns active status" do
        result = described_class.migrate(content, original_anchor)
        expect(result["status"]).to eq(Docsmith::Comments::Anchor::ACTIVE)
      end
    end

    context "when anchored text has moved but still exists" do
      let(:new_content) { "A quick brown fox jumps over the lazy dog" }

      it "returns drifted status with updated offsets" do
        result = described_class.migrate(new_content, original_anchor)
        expect(result["status"]).to eq(Docsmith::Comments::Anchor::DRIFTED)
        expect(result["start_offset"]).to eq(new_content.index("quick"))
      end
    end

    context "when anchored text no longer exists" do
      let(:new_content) { "Completely different content here" }

      it "returns orphaned status" do
        result = described_class.migrate(new_content, original_anchor)
        expect(result["status"]).to eq(Docsmith::Comments::Anchor::ORPHANED)
      end
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/comments/anchor_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Comments::Anchor`

- [ ] **Step 3: Implement**

```ruby
# lib/docsmith/comments/anchor.rb
# frozen_string_literal: true

require "digest"

module Docsmith
  module Comments
    # Builds and migrates range anchors for inline comments.
    # An anchor captures character offsets and a content hash of the selected text
    # so the comment can be relocated when content changes between versions.
    module Anchor
      ACTIVE   = "active"
      DRIFTED  = "drifted"
      ORPHANED = "orphaned"

      # Builds anchor_data for a new range comment.
      #
      # @param content [String] the version content at comment time
      # @param start_offset [Integer] character offset of selection start (inclusive)
      # @param end_offset [Integer] character offset of selection end (exclusive)
      # @return [Hash] anchor_data hash ready to store on the Comment
      def self.build(content, start_offset:, end_offset:)
        anchored_text = content[start_offset...end_offset].to_s
        {
          start_offset:  start_offset,
          end_offset:    end_offset,
          content_hash:  Digest::SHA256.hexdigest(anchored_text),
          anchored_text: anchored_text,
          status:        ACTIVE
        }
      end

      # Attempts to migrate an existing anchor to new version content.
      #
      # Strategy:
      # 1. Try exact offset — if SHA256 of text at same offsets matches, return ACTIVE.
      # 2. Search the full content for the original anchored text — return DRIFTED with new offsets.
      # 3. If not found anywhere, return ORPHANED.
      #
      # @param content [String] new version content
      # @param anchor_data [Hash] existing anchor_data (string keys from JSON storage)
      # @return [Hash] updated anchor_data with new :status
      def self.migrate(content, anchor_data)
        start_off     = anchor_data["start_offset"]
        end_off       = anchor_data["end_offset"]
        original_hash = anchor_data["content_hash"]
        original_text = anchor_data["anchored_text"]

        # 1. Exact offset check
        candidate = content[start_off...end_off].to_s
        return anchor_data.merge("status" => ACTIVE) if Digest::SHA256.hexdigest(candidate) == original_hash

        # 2. Full-text search for relocated text
        idx = content.index(original_text)
        if idx
          new_end = idx + original_text.length
          return anchor_data.merge(
            "start_offset" => idx,
            "end_offset"   => new_end,
            "status"       => DRIFTED
          )
        end

        # 3. Orphaned — text no longer exists
        anchor_data.merge("status" => ORPHANED)
      end
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/comments/anchor_spec.rb
```

Expected: `7 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/comments/anchor.rb spec/docsmith/comments/anchor_spec.rb
git commit -m "feat(comments): add Comments::Anchor for range anchor build and migration

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 3.4 — `Comments::Manager` (add! + resolve!)

**Files:**
- Create: `lib/docsmith/comments/manager.rb`
- Create: `spec/docsmith/comments/manager_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/comments/manager_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Comments::Manager do
  include FactoryBot::Syntax::Methods

  let(:user)    { create(:user) }
  let(:doc)     { create(:document, content: "hello world content here", content_type: "markdown") }
  let!(:version) { create(:document_version, document: doc, content: "hello world content here", version_number: 1, content_type: "markdown") }

  describe ".add!" do
    context "document-level comment" do
      it "creates a Comment with anchor_type document" do
        comment = described_class.add!(doc, version_number: 1, body: "Looks good", author: user)
        expect(comment).to be_a(Docsmith::Comments::Comment)
        expect(comment.anchor_type).to eq("document")
        expect(comment.body).to eq("Looks good")
        expect(comment.version).to eq(version)
      end

      it "fires the :comment_added hook with the comment payload" do
        fired = []
        Docsmith.configuration.on(:comment_added) { |e| fired << e }
        described_class.add!(doc, version_number: 1, body: "hello", author: user)
        expect(fired.length).to eq(1)
        expect(fired.first.comment.body).to eq("hello")
      end

      it "emits comment_added.docsmith AS::Notifications event" do
        received = []
        sub = ActiveSupport::Notifications.subscribe("comment_added.docsmith") { |*args| received << args }
        described_class.add!(doc, version_number: 1, body: "hello", author: user)
        ActiveSupport::Notifications.unsubscribe(sub)
        expect(received).not_to be_empty
      end
    end

    context "range-anchored inline comment" do
      it "creates a Comment with anchor_type range and computed anchor_data" do
        comment = described_class.add!(
          doc, version_number: 1, body: "cite this",
          author: user, anchor: { start_offset: 0, end_offset: 5 }
        )
        expect(comment.anchor_type).to eq("range")
        expect(comment.anchor_data["anchored_text"]).to eq("hello")
        expect(comment.anchor_data["status"]).to eq(Docsmith::Comments::Anchor::ACTIVE)
      end
    end

    context "threaded reply" do
      it "sets parent on the reply" do
        parent = described_class.add!(doc, version_number: 1, body: "original", author: user)
        reply  = described_class.add!(doc, version_number: 1, body: "reply", author: user, parent: parent)
        expect(reply.parent).to eq(parent)
      end
    end

    it "raises ActiveRecord::RecordNotFound for a non-existent version" do
      expect {
        described_class.add!(doc, version_number: 99, body: "x", author: user)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe ".resolve!" do
    let!(:comment) { described_class.add!(doc, version_number: 1, body: "needs fix", author: user) }

    it "marks the comment resolved and sets resolved_by" do
      described_class.resolve!(comment, by: user)
      expect(comment.reload.resolved).to be(true)
      expect(comment.resolved_by).to eq(user)
    end

    it "fires the :comment_resolved hook" do
      fired = []
      Docsmith.configuration.on(:comment_resolved) { |e| fired << e }
      described_class.resolve!(comment, by: user)
      expect(fired.length).to eq(1)
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/comments/manager_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Comments::Manager`

- [ ] **Step 3: Implement**

```ruby
# lib/docsmith/comments/manager.rb
# frozen_string_literal: true

module Docsmith
  module Comments
    # Service object for creating and resolving comments on document versions.
    class Manager
      class << self
        # Adds a comment to a specific version of a document.
        #
        # @param document [Docsmith::Document]
        # @param version_number [Integer]
        # @param body [String]
        # @param author [Object] polymorphic author record
        # @param anchor [Hash, nil] { start_offset:, end_offset: } for inline range comments
        # @param parent [Comments::Comment, nil] parent comment for threading
        # @return [Comments::Comment]
        # @raise [ActiveRecord::RecordNotFound] if version_number does not exist
        def add!(document, version_number:, body:, author:, anchor: nil, parent: nil)
          version = Docsmith::DocumentVersion.find_by!(document: document, version_number: version_number)

          anchor_type = anchor ? "range" : "document"
          anchor_data = anchor ? Anchor.build(version.content.to_s, start_offset: anchor[:start_offset], end_offset: anchor[:end_offset]) : {}

          comment = Comment.create!(
            version:     version,
            author:      author,
            body:        body,
            anchor_type: anchor_type,
            anchor_data: anchor_data,
            parent:      parent,
            resolved:    false
          )

          fire_event(:comment_added, document: document, version: version, author: author, comment: comment)
          comment
        end

        # Marks a comment as resolved.
        #
        # @param comment [Comments::Comment]
        # @param by [Object] polymorphic resolver record
        # @return [Comments::Comment]
        def resolve!(comment, by:)
          comment.update!(resolved: true, resolved_by: by, resolved_at: Time.current)

          document = comment.version.document
          fire_event(:comment_resolved, document: document, version: comment.version, author: by, comment: comment)
          comment
        end

        private

        def fire_event(name, document:, version:, author:, comment:)
          event = Events::Event.new(
            name:     name,
            record:   document.subject || document,
            document: document,
            version:  version,
            author:   author,
            comment:  comment
          )
          Events::HookRegistry.fire(name, event)
          Events::Notifier.instrument("#{name}.docsmith", event)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/comments/manager_spec.rb
```

Expected: `10 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/comments/manager.rb spec/docsmith/comments/manager_spec.rb
git commit -m "feat(comments): add Comments::Manager with add! and resolve!

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 3.5 — `Comments::Migrator`

**Files:**
- Create: `lib/docsmith/comments/migrator.rb`
- Create: `spec/docsmith/comments/migrator_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/comments/migrator_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Comments::Migrator do
  include FactoryBot::Syntax::Methods

  let(:user)     { create(:user) }
  let(:doc)      { create(:document, content: "hello world content", content_type: "markdown") }
  let!(:version1) { create(:document_version, document: doc, content: "hello world content", version_number: 1, content_type: "markdown") }
  let!(:version2) { create(:document_version, document: doc, content: "hello world content updated", version_number: 2, content_type: "markdown") }
  let!(:version3) { create(:document_version, document: doc, content: "completely different", version_number: 3, content_type: "markdown") }

  describe ".migrate!" do
    context "document-level comment" do
      before { Docsmith::Comments::Manager.add!(doc, version_number: 1, body: "good", author: user) }

      it "copies the comment body and anchor_type to the new version" do
        described_class.migrate!(doc, from: 1, to: 2)
        new_comments = Docsmith::Comments::Comment.where(version: version2)
        expect(new_comments.count).to eq(1)
        expect(new_comments.first.body).to eq("good")
        expect(new_comments.first.anchor_type).to eq("document")
      end
    end

    context "range-anchored comment where anchored text is still present" do
      before do
        Docsmith::Comments::Manager.add!(
          doc, version_number: 1, body: "note",
          author: user, anchor: { start_offset: 0, end_offset: 5 }
        )
      end

      it "migrates with active or drifted status (text found in new version)" do
        described_class.migrate!(doc, from: 1, to: 2)
        new_comment = Docsmith::Comments::Comment.where(version: version2).first
        expect(new_comment.anchor_data["status"]).to be_in([
          Docsmith::Comments::Anchor::ACTIVE,
          Docsmith::Comments::Anchor::DRIFTED
        ])
      end
    end

    context "range-anchored comment where anchored text is gone" do
      before do
        Docsmith::Comments::Manager.add!(
          doc, version_number: 1, body: "note",
          author: user, anchor: { start_offset: 0, end_offset: 5 }
        )
      end

      it "fires :comment_orphaned event and sets orphaned status" do
        fired = []
        Docsmith.configuration.on(:comment_orphaned) { |e| fired << e }
        described_class.migrate!(doc, from: 1, to: 3)
        expect(fired).not_to be_empty
        expect(fired.first.comment.anchor_data["status"]).to eq(Docsmith::Comments::Anchor::ORPHANED)
      end
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/comments/migrator_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Comments::Migrator`

- [ ] **Step 3: Implement**

```ruby
# lib/docsmith/comments/migrator.rb
# frozen_string_literal: true

module Docsmith
  module Comments
    # Migrates top-level comments from one version to another.
    # Document-level comments are copied as-is.
    # Range-anchored comments are re-anchored using Anchor.migrate;
    # orphaned comments fire the :comment_orphaned event.
    class Migrator
      class << self
        # @param document [Docsmith::Document]
        # @param from [Integer] source version_number
        # @param to [Integer] target version_number
        # @return [void]
        def migrate!(document, from:, to:)
          from_version = Docsmith::DocumentVersion.find_by!(document: document, version_number: from)
          to_version   = Docsmith::DocumentVersion.find_by!(document: document, version_number: to)
          new_content  = to_version.content.to_s

          from_version.comments.top_level.each do |comment|
            new_anchor_data = migrate_anchor(comment, new_content)

            new_comment = Comment.create!(
              version:          to_version,
              author_type:      comment.author_type,
              author_id:        comment.author_id,
              body:             comment.body,
              anchor_type:      comment.anchor_type,
              anchor_data:      new_anchor_data,
              resolved:         comment.resolved,
              resolved_by_type: comment.resolved_by_type,
              resolved_by_id:   comment.resolved_by_id,
              resolved_at:      comment.resolved_at
            )

            fire_orphaned_event(document, to_version, new_comment) if orphaned?(comment, new_anchor_data)
          end
        end

        private

        def migrate_anchor(comment, new_content)
          return comment.anchor_data if comment.anchor_type == "document"

          Anchor.migrate(new_content, comment.anchor_data)
        end

        def orphaned?(comment, new_anchor_data)
          comment.anchor_type == "range" && new_anchor_data["status"] == Anchor::ORPHANED
        end

        def fire_orphaned_event(document, version, comment)
          event = Events::Event.new(
            name:     :comment_orphaned,
            record:   document.subject || document,
            document: document,
            version:  version,
            author:   nil,
            comment:  comment
          )
          Events::HookRegistry.fire(:comment_orphaned, event)
          Events::Notifier.instrument("comment_orphaned.docsmith", event)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/comments/migrator_spec.rb
```

Expected: `4 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/comments/migrator.rb spec/docsmith/comments/migrator_spec.rb
git commit -m "feat(comments): add Comments::Migrator for cross-version comment migration

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 3.6 — Versionable comment methods

**Files:**
- Modify: `lib/docsmith/versionable.rb`
- Test: append to `spec/docsmith/versionable_spec.rb`

- [ ] **Step 1: Write the failing tests** (append inside the existing `RSpec.describe Docsmith::Versionable` block)

```ruby
describe "#add_comment!" do
  include FactoryBot::Syntax::Methods

  let(:article) { create(:article, body: "hello world content here") }
  let(:user)    { create(:user) }

  before { article.save_version!(author: user) }

  it "creates a document-level comment on the specified version" do
    comment = article.add_comment!(version: 1, body: "Great", author: user)
    expect(comment).to be_a(Docsmith::Comments::Comment)
    expect(comment.anchor_type).to eq("document")
  end

  it "creates a range-anchored inline comment when anchor is given" do
    comment = article.add_comment!(
      version: 1, body: "cite", author: user,
      anchor: { start_offset: 0, end_offset: 5 }
    )
    expect(comment.anchor_type).to eq("range")
  end
end

describe "#comments" do
  include FactoryBot::Syntax::Methods

  let(:article) { create(:article, body: "content") }
  let(:user)    { create(:user) }

  before do
    article.save_version!(author: user)
    article.add_comment!(version: 1, body: "first",  author: user)
    article.add_comment!(version: 1, body: "second", author: user)
  end

  it "returns all comments across all versions as an AR relation" do
    expect(article.comments.count).to eq(2)
  end
end

describe "#comments_on" do
  include FactoryBot::Syntax::Methods

  let(:article) { create(:article, body: "content") }
  let(:user)    { create(:user) }

  before do
    article.save_version!(author: user)
    article.body = "updated"
    article.save!
    article.save_version!(author: user)
    article.add_comment!(version: 1, body: "on v1", author: user)
    article.add_comment!(version: 2, body: "on v2", author: user)
  end

  it "returns only comments on the specified version" do
    expect(article.comments_on(version: 1).map(&:body)).to eq(["on v1"])
    expect(article.comments_on(version: 2).map(&:body)).to eq(["on v2"])
  end
end

describe "#unresolved_comments" do
  include FactoryBot::Syntax::Methods

  let(:article) { create(:article, body: "content") }
  let(:user)    { create(:user) }

  before do
    article.save_version!(author: user)
    article.add_comment!(version: 1, body: "unresolved", author: user)
    c2 = article.add_comment!(version: 1, body: "resolved",   author: user)
    Docsmith::Comments::Manager.resolve!(c2, by: user)
  end

  it "returns only unresolved comments" do
    expect(article.unresolved_comments.count).to eq(1)
    expect(article.unresolved_comments.first.body).to eq("unresolved")
  end
end

describe "#migrate_comments!" do
  include FactoryBot::Syntax::Methods

  let(:article) { create(:article, body: "hello world") }
  let(:user)    { create(:user) }

  before do
    article.save_version!(author: user)
    article.add_comment!(version: 1, body: "note", author: user)
    article.body = "hello world updated"
    article.save!
    article.save_version!(author: user)
  end

  it "copies comments from one version to another" do
    article.migrate_comments!(from: 1, to: 2)
    expect(article.comments_on(version: 2).count).to eq(1)
    expect(article.comments_on(version: 2).first.body).to eq("note")
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb
```

Expected: `NoMethodError: undefined method 'add_comment!'`

- [ ] **Step 3: Add methods to Versionable** (inside the public instance methods section)

```ruby
# Adds a comment to a specific version of this document.
#
# @param version [Integer] version_number
# @param body [String]
# @param author [Object] polymorphic author
# @param anchor [Hash, nil] { start_offset:, end_offset: } for inline range comments
# @param parent [Comments::Comment, nil] parent comment for threading
# @return [Docsmith::Comments::Comment]
def add_comment!(version:, body:, author:, anchor: nil, parent: nil)
  Comments::Manager.add!(
    _docsmith_document,
    version_number: version,
    body:           body,
    author:         author,
    anchor:         anchor,
    parent:         parent
  )
end

# Returns all comments across all versions of this document.
#
# @return [ActiveRecord::Relation<Docsmith::Comments::Comment>]
def comments
  doc = _docsmith_document
  Comments::Comment.joins(:version)
                   .where(docsmith_versions: { document_id: doc.id })
end

# Returns comments on a specific version, optionally filtered by anchor type.
#
# @param version [Integer] version_number
# @param type [Symbol, nil] :document or :range to filter; nil = all
# @return [ActiveRecord::Relation<Docsmith::Comments::Comment>]
def comments_on(version:, type: nil)
  doc = _docsmith_document
  dv  = Docsmith::DocumentVersion.find_by!(document: doc, version_number: version)
  rel = Comments::Comment.where(version: dv)
  rel = rel.where(anchor_type: type.to_s) if type
  rel
end

# Returns all unresolved comments across all versions.
#
# @return [ActiveRecord::Relation<Docsmith::Comments::Comment>]
def unresolved_comments
  comments.merge(Comments::Comment.unresolved)
end

# Migrates top-level comments from one version to another.
#
# @param from [Integer] source version_number
# @param to [Integer] target version_number
# @return [void]
def migrate_comments!(from:, to:)
  Comments::Migrator.migrate!(_docsmith_document, from: from, to: to)
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb
```

Expected: all examples pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/versionable.rb spec/docsmith/versionable_spec.rb
git commit -m "feat(comments): add Versionable comment methods (add_comment!, comments, migrate_comments!)

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 3.7 — Wire Phase 3 requires + integration test

**Files:**
- Modify: `lib/docsmith.rb`
- Create: `spec/docsmith/phase3_integration_spec.rb`

- [ ] **Step 1: Add Phase 3 requires to `lib/docsmith.rb`** (after Phase 2 requires)

```ruby
require_relative "docsmith/comments/comment"
require_relative "docsmith/comments/anchor"
require_relative "docsmith/comments/manager"
require_relative "docsmith/comments/migrator"
```

- [ ] **Step 2: Write the failing integration test**

```ruby
# spec/docsmith/phase3_integration_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Phase 3: Comments & Inline Annotations integration" do
  include FactoryBot::Syntax::Methods

  let(:user)    { create(:user) }
  let(:article) { create(:article, body: "hello world content here for testing") }

  before do
    article.save_version!(author: user)
    article.body = "hello world content updated here"
    article.save!
    article.save_version!(author: user)
  end

  it "adds a document-level comment" do
    comment = article.add_comment!(version: 1, body: "Nice intro", author: user)
    expect(comment.anchor_type).to eq("document")
    expect(article.comments.count).to eq(1)
  end

  it "adds a range-anchored inline comment" do
    comment = article.add_comment!(
      version: 1, body: "Cite this", author: user,
      anchor: { start_offset: 0, end_offset: 5 }
    )
    expect(comment.anchor_type).to eq("range")
    expect(comment.anchor_data["anchored_text"]).to eq("hello")
  end

  it "creates threaded replies" do
    parent = article.add_comment!(version: 1, body: "original", author: user)
    reply  = article.add_comment!(version: 1, body: "reply",    author: user, parent: parent)
    expect(reply.parent).to eq(parent)
    expect(parent.replies).to include(reply)
  end

  it "resolves a comment" do
    comment = article.add_comment!(version: 1, body: "fix this", author: user)
    Docsmith::Comments::Manager.resolve!(comment, by: user)
    expect(article.unresolved_comments.count).to eq(0)
  end

  it "migrates document-level comments to a new version" do
    article.add_comment!(version: 1, body: "good", author: user)
    article.migrate_comments!(from: 1, to: 2)
    expect(article.comments_on(version: 2).count).to eq(1)
    expect(article.comments_on(version: 2).first.body).to eq("good")
  end

  it "tracks unresolved comments across versions" do
    article.add_comment!(version: 1, body: "pending",      author: user)
    article.add_comment!(version: 2, body: "also pending", author: user)
    expect(article.unresolved_comments.count).to eq(2)
  end
end
```

- [ ] **Step 3: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/phase3_integration_spec.rb
```

Expected: `6 examples, 0 failures`

- [ ] **Step 4: Run the full Phase 1+2+3 suite**

```bash
bundle exec rspec spec/
```

Expected: all examples pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith.rb spec/docsmith/phase3_integration_spec.rb
git commit -m "feat(comments): wire Phase 3 requires and add integration test

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

**Phase 3 complete.** 7 tasks implemented and tested.
Run `bundle exec rspec spec/` to confirm green before proceeding to Phase 4.


---

## File Map — Phase 4

| File | Action | Responsibility |
|---|---|---|
| `spec/support/schema.rb` | Modify | Add `docsmith_branches` table + `branch_id` to `docsmith_versions` |
| `lib/generators/docsmith/install/templates/create_docsmith_tables.rb.erb` | Modify | Add `docsmith_branches` migration block + `branch_id` column |
| `lib/docsmith/events/event.rb` | Modify | Add `branch` and `merge_result` fields to Event struct |
| `lib/docsmith/document_version.rb` | Modify | Add `belongs_to :branch` association |
| `lib/docsmith/merge_result.rb` | Create | `MergeResult` value object |
| `lib/docsmith/branches/branch.rb` | Create | `Docsmith::Branches::Branch` AR model |
| `lib/docsmith/branches/merger.rb` | Create | Fast-forward + three-way merge logic |
| `lib/docsmith/branches/manager.rb` | Create | `create!` and `merge!` service |
| `lib/docsmith/version_manager.rb` | Modify | Support `branch:` keyword on `save!` |
| `lib/docsmith/versionable.rb` | Modify | Add `create_branch!`, `branches`, `active_branches`, `merge_branch!` + `branch:` on `save_version!` |
| `lib/docsmith.rb` | Modify | Require Phase 4 files |
| `spec/docsmith/merge_result_spec.rb` | Create | MergeResult specs |
| `spec/docsmith/branches/branch_spec.rb` | Create | Branch model specs |
| `spec/docsmith/branches/merger_spec.rb` | Create | Merger unit specs |
| `spec/docsmith/branches/manager_spec.rb` | Create | Manager service specs |
| `spec/docsmith/phase4_integration_spec.rb` | Create | End-to-end Phase 4 test |

---

## Phase 4: Branching & Merging

### Task 4.1 — Schema update + `branch_id` on versions

**Files:**
- Modify: `spec/support/schema.rb`
- Modify: `lib/generators/docsmith/install/templates/create_docsmith_tables.rb.erb`
- Modify: `lib/docsmith/events/event.rb`
- Modify: `lib/docsmith/document_version.rb`

- [ ] **Step 1: Add `docsmith_branches` table and `branch_id` column to test schema**

Append inside the `ActiveRecord::Schema.define` block in `spec/support/schema.rb`:

```ruby
create_table :docsmith_branches, force: true do |t|
  t.bigint   :document_id,       null: false
  t.string   :name,              null: false
  t.bigint   :source_version_id, null: false
  t.bigint   :head_version_id
  t.string   :author_type
  t.bigint   :author_id
  t.string   :status,            null: false, default: "active"
  t.datetime :merged_at
  t.datetime :created_at,        null: false
  t.datetime :updated_at,        null: false
end

add_index :docsmith_branches, [:document_id, :name], unique: true
```

Also update the `docsmith_versions` table definition in `spec/support/schema.rb` to add `branch_id`:

```ruby
t.bigint :branch_id   # null = main branch; non-null = branch version
```

And add the index after the table:

```ruby
add_index :docsmith_versions, :branch_id
```

- [ ] **Step 2: Add to migration template**

Append to `lib/generators/docsmith/install/templates/create_docsmith_tables.rb.erb` inside `change`:

```ruby
create_table :docsmith_branches do |t|
  t.bigint   :document_id,       null: false
  t.string   :name,              null: false
  t.bigint   :source_version_id, null: false
  t.bigint   :head_version_id
  t.string   :author_type
  t.bigint   :author_id
  t.string   :status,            null: false, default: "active"
  t.datetime :merged_at
  t.timestamps                   null: false
end

add_index :docsmith_branches, [:document_id, :name], unique: true
add_foreign_key :docsmith_branches, :docsmith_documents, column: :document_id
add_foreign_key :docsmith_branches, :docsmith_versions,  column: :source_version_id
add_foreign_key :docsmith_branches, :docsmith_versions,  column: :head_version_id
```

Also add `branch_id` to the `docsmith_versions` table block in the template:

```ruby
t.bigint :branch_id
```

And add index:

```ruby
add_index :docsmith_versions, :branch_id
```

- [ ] **Step 3: Add `branch` and `merge_result` to Event struct**

In `lib/docsmith/events/event.rb`, update the Struct:

```ruby
# Change from:
Docsmith::Events::Event = Struct.new(
  :name, :record, :document, :version, :author, :from_version, :tag_name, :comment,
  keyword_init: true
)

# Change to:
Docsmith::Events::Event = Struct.new(
  :name, :record, :document, :version, :author,
  :from_version, :tag_name, :comment, :branch, :merge_result,
  keyword_init: true
)
```

- [ ] **Step 4: Add `belongs_to :branch` to DocumentVersion**

In `lib/docsmith/document_version.rb`, add inside the class body:

```ruby
belongs_to :branch, class_name: "Docsmith::Branches::Branch", optional: true
```

- [ ] **Step 5: Run the full suite — confirm no regressions**

```bash
bundle exec rspec spec/
```

Expected: all Phase 1+2+3 examples pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add spec/support/schema.rb \
        lib/generators/docsmith/install/templates/create_docsmith_tables.rb.erb \
        lib/docsmith/events/event.rb \
        lib/docsmith/document_version.rb
git commit -m "feat(branches): add docsmith_branches schema, branch_id on versions, Event fields

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 4.2 — `MergeResult` + `Branches::Branch` AR model

**Files:**
- Create: `lib/docsmith/merge_result.rb`
- Create: `spec/docsmith/merge_result_spec.rb`
- Create: `lib/docsmith/branches/branch.rb`
- Create: `spec/docsmith/branches/branch_spec.rb`

- [ ] **Step 1: Write the failing MergeResult test**

```ruby
# spec/docsmith/merge_result_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::MergeResult do
  describe "successful merge" do
    let(:version) { double("version") }
    subject(:result) { described_class.new(merged_version: version, conflicts: []) }

    it "is successful" do
      expect(result.success?).to be(true)
    end

    it "has no conflicts" do
      expect(result.conflicts).to be_empty
    end

    it "exposes the merged version" do
      expect(result.merged_version).to eq(version)
    end
  end

  describe "conflicted merge" do
    subject(:result) do
      described_class.new(
        merged_version: nil,
        conflicts: [{ line: 3, branch_content: "branch text", main_content: "main text" }]
      )
    end

    it "is not successful" do
      expect(result.success?).to be(false)
    end

    it "exposes the conflict descriptions" do
      expect(result.conflicts.first[:line]).to eq(3)
    end

    it "has no merged_version" do
      expect(result.merged_version).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/merge_result_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::MergeResult`

- [ ] **Step 3: Implement MergeResult**

```ruby
# lib/docsmith/merge_result.rb
# frozen_string_literal: true

module Docsmith
  # The result object returned by merge_branch!.
  # On success: merged_version holds the newly created DocumentVersion.
  # On conflict: conflicts holds an array of conflict description hashes
  #   (each with :line, :base_content, :main_content, :branch_content).
  class MergeResult
    # @return [Docsmith::DocumentVersion, nil]
    attr_reader :merged_version
    # @return [Array<Hash>]
    attr_reader :conflicts

    # @param merged_version [Docsmith::DocumentVersion, nil]
    # @param conflicts [Array<Hash>]
    def initialize(merged_version:, conflicts:)
      @merged_version = merged_version
      @conflicts      = conflicts
    end

    # @return [Boolean] true when merge succeeded with no conflicts
    def success?
      conflicts.empty?
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/merge_result_spec.rb
```

Expected: `6 examples, 0 failures`

- [ ] **Step 5: Write the failing Branch model test**

```ruby
# spec/docsmith/branches/branch_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Branches::Branch do
  include FactoryBot::Syntax::Methods

  let(:user)    { create(:user) }
  let(:doc)     { create(:document, content: "initial content", content_type: "markdown") }
  let(:version) { create(:document_version, document: doc, content: "initial content", version_number: 1, content_type: "markdown") }

  describe "associations" do
    it "belongs to a document" do
      branch = described_class.create!(document: doc, name: "feature", source_version: version, author: user, status: "active")
      expect(branch.document).to eq(doc)
    end

    it "belongs to source_version" do
      branch = described_class.create!(document: doc, name: "feature", source_version: version, author: user, status: "active")
      expect(branch.source_version).to eq(version)
    end
  end

  describe "validations" do
    it "enforces unique name per document at DB level" do
      described_class.create!(document: doc, name: "feature", source_version: version, author: user, status: "active")
      duplicate = described_class.new(document: doc, name: "feature", source_version: version, author: user, status: "active")
      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "validates status inclusion" do
      branch = described_class.new(document: doc, name: "b", source_version: version, author: user, status: "invalid")
      expect(branch).not_to be_valid
    end
  end

  describe "scopes" do
    before do
      described_class.create!(document: doc, name: "active-one",  source_version: version, author: user, status: "active")
      described_class.create!(document: doc, name: "merged-one",  source_version: version, author: user, status: "merged")
      described_class.create!(document: doc, name: "abandoned",   source_version: version, author: user, status: "abandoned")
    end

    it ".active returns only active branches" do
      expect(described_class.active.count).to eq(1)
    end

    it ".merged returns only merged branches" do
      expect(described_class.merged.count).to eq(1)
    end
  end
end
```

- [ ] **Step 6: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/branches/branch_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Branches`

- [ ] **Step 7: Create directory and implement Branch**

```bash
mkdir -p lib/docsmith/branches spec/docsmith/branches
```

```ruby
# lib/docsmith/branches/branch.rb
# frozen_string_literal: true

module Docsmith
  module Branches
    # Represents a named branch of a document's version history.
    # Branches fork from source_version and accumulate versions independently.
    # On merge, a new version is created on the main document history.
    class Branch < ActiveRecord::Base
      self.table_name = "docsmith_branches"

      STATUSES = %w[active merged abandoned].freeze

      belongs_to :document,       class_name: "Docsmith::Document"
      belongs_to :source_version, class_name: "Docsmith::DocumentVersion", foreign_key: :source_version_id
      belongs_to :head_version,   class_name: "Docsmith::DocumentVersion", foreign_key: :head_version_id, optional: true
      belongs_to :author,         polymorphic: true, optional: true

      validates :name,   presence: true
      validates :status, inclusion: { in: STATUSES }

      scope :active,    -> { where(status: "active") }
      scope :merged,    -> { where(status: "merged") }
      scope :abandoned, -> { where(status: "abandoned") }

      # Returns all DocumentVersions on this branch.
      #
      # @return [ActiveRecord::Relation<Docsmith::DocumentVersion>]
      def versions
        Docsmith::DocumentVersion.where(branch_id: id).order(:version_number)
      end

      # Returns the latest version on this branch (head_version association).
      #
      # @return [Docsmith::DocumentVersion, nil]
      def head
        head_version
      end

      # Computes a diff between the source_version (fork point) and the branch head.
      #
      # @return [Docsmith::Diff::Result, nil] nil if branch has no versions yet
      def diff_from_source
        return nil unless head_version

        Docsmith::Diff.between(source_version, head_version)
      end

      # Computes a diff between the branch head and the current main head.
      #
      # @return [Docsmith::Diff::Result, nil] nil if branch has no versions yet
      def diff_against_current
        return nil unless head_version

        main_head = document.versions.where(branch_id: nil).order(version_number: :desc).first
        return nil unless main_head

        Docsmith::Diff.between(head_version, main_head)
      end
    end
  end
end
```

- [ ] **Step 8: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/branches/branch_spec.rb spec/docsmith/merge_result_spec.rb
```

Expected: `11 examples, 0 failures`

- [ ] **Step 9: Commit**

```bash
git add lib/docsmith/merge_result.rb spec/docsmith/merge_result_spec.rb \
        lib/docsmith/branches/branch.rb spec/docsmith/branches/branch_spec.rb
git commit -m "feat(branches): add MergeResult value object and Branches::Branch AR model

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 4.3 — `Branches::Merger` (fast-forward + three-way merge)

**Files:**
- Create: `lib/docsmith/branches/merger.rb`
- Create: `spec/docsmith/branches/merger_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/branches/merger_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Branches::Merger do
  include FactoryBot::Syntax::Methods

  let(:doc)    { create(:document, content: "line one\nline two\nline three", content_type: "markdown") }
  let(:source) { create(:document_version, document: doc, content: "line one\nline two\nline three", version_number: 1, content_type: "markdown") }

  describe ".merge" do
    context "fast-forward (main_head is the source_version)" do
      let(:branch_head) do
        create(:document_version, document: doc, content: "line one\nline two\nline three\nline four",
               version_number: 2, content_type: "markdown")
      end

      it "returns a successful result with no conflicts" do
        result = described_class.merge(source_version: source, branch_head: branch_head, main_head: source)
        expect(result.success?).to be(true)
        expect(result.conflicts).to be_empty
      end

      it "merged_content equals branch head content" do
        result = described_class.merge(source_version: source, branch_head: branch_head, main_head: source)
        expect(result.merged_content).to eq(branch_head.content)
      end
    end

    context "three-way merge with non-overlapping changes" do
      # source: "line one\nline two\nline three"
      # main edits line 2; branch adds line 4
      # expected: "line one\nline two edited\nline three\nline four"
      let(:main_head) do
        create(:document_version, document: doc, content: "line one\nline two edited\nline three",
               version_number: 2, content_type: "markdown")
      end
      let(:branch_head) do
        create(:document_version, document: doc, content: "line one\nline two\nline three\nline four",
               version_number: 3, content_type: "markdown")
      end

      it "auto-merges and returns success" do
        result = described_class.merge(source_version: source, branch_head: branch_head, main_head: main_head)
        expect(result.success?).to be(true)
        expect(result.merged_content).to include("line two edited")
        expect(result.merged_content).to include("line four")
      end
    end

    context "three-way merge with conflicting changes on the same line" do
      # source: "line one\nline two\nline three"
      # main changes line 2 to "MAIN EDIT"; branch changes line 2 to "BRANCH EDIT"
      let(:main_head) do
        create(:document_version, document: doc, content: "line one\nMAIN EDIT\nline three",
               version_number: 2, content_type: "markdown")
      end
      let(:branch_head) do
        create(:document_version, document: doc, content: "line one\nBRANCH EDIT\nline three",
               version_number: 3, content_type: "markdown")
      end

      it "returns unsuccessful result with conflicts" do
        result = described_class.merge(source_version: source, branch_head: branch_head, main_head: main_head)
        expect(result.success?).to be(false)
        expect(result.conflicts).not_to be_empty
      end

      it "sets merged_content to nil on conflict" do
        result = described_class.merge(source_version: source, branch_head: branch_head, main_head: main_head)
        expect(result.merged_content).to be_nil
      end

      it "includes conflict details for each conflicting line" do
        result = described_class.merge(source_version: source, branch_head: branch_head, main_head: main_head)
        conflict = result.conflicts.first
        expect(conflict[:line]).to eq(2)
        expect(conflict[:main_content]).to eq("MAIN EDIT")
        expect(conflict[:branch_content]).to eq("BRANCH EDIT")
      end
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/branches/merger_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Branches::Merger`

- [ ] **Step 3: Implement**

```ruby
# lib/docsmith/branches/merger.rb
# frozen_string_literal: true

require "diff/lcs"

module Docsmith
  module Branches
    # Three-way merge engine for document branches using line-level diff-lcs.
    #
    # Fast-forward: when main_head == source_version, branch content wins outright.
    # Three-way:    detect changes from source→main and source→branch.
    #               Auto-merge non-overlapping changes.
    #               Return conflicts for lines changed differently on both sides.
    class Merger
      # Internal struct — distinct from the public MergeResult (which has a persisted version).
      # merged_content is a String on success, nil on conflict.
      InternalResult = Struct.new(:merged_content, :conflicts, keyword_init: true) do
        def success?
          conflicts.empty?
        end
      end

      class << self
        # @param source_version [Docsmith::DocumentVersion] common ancestor (fork point)
        # @param branch_head    [Docsmith::DocumentVersion] latest version on the branch
        # @param main_head      [Docsmith::DocumentVersion] latest version on main
        # @return [InternalResult]
        def merge(source_version:, branch_head:, main_head:)
          # Fast-forward: main hasn't changed since the branch was created
          if main_head.id == source_version.id
            return InternalResult.new(merged_content: branch_head.content.to_s, conflicts: [])
          end

          three_way_merge(
            base:   source_version.content.to_s,
            ours:   main_head.content.to_s,
            theirs: branch_head.content.to_s
          )
        end

        private

        # Line-level three-way merge.
        # Applies non-conflicting changes from both sides onto the base.
        # Returns a conflict for each line changed differently by both sides.
        def three_way_merge(base:, ours:, theirs:)
          base_lines   = base.split("\n", -1)
          ours_lines   = ours.split("\n", -1)
          theirs_lines = theirs.split("\n", -1)

          ours_changes   = line_changes(base_lines, ours_lines)
          theirs_changes = line_changes(base_lines, theirs_lines)

          conflicts = detect_conflicts(base_lines, ours_changes, theirs_changes)
          return InternalResult.new(merged_content: nil, conflicts: conflicts) if conflicts.any?

          merged = apply_changes(base_lines, ours_lines, theirs_lines, ours_changes, theirs_changes)
          InternalResult.new(merged_content: merged.join("\n"), conflicts: [])
        end

        # Returns hash of { line_index => new_content } for lines changed vs base.
        # Deletions stored as nil. Pure insertions (action "+") are handled via length checks.
        def line_changes(base_lines, new_lines)
          changes = {}
          ::Diff::LCS.sdiff(base_lines, new_lines).each do |hunk|
            case hunk.action
            when "!" then changes[hunk.old_position] = hunk.new_element
            when "-" then changes[hunk.old_position] = nil
            end
          end
          changes
        end

        # Detects lines changed differently by both sides.
        def detect_conflicts(base_lines, ours_changes, theirs_changes)
          conflicts = []
          (ours_changes.keys & theirs_changes.keys).each do |idx|
            next if ours_changes[idx] == theirs_changes[idx]  # identical change — no conflict

            conflicts << {
              line:           idx + 1,
              base_content:   base_lines[idx],
              main_content:   ours_changes[idx],
              branch_content: theirs_changes[idx]
            }
          end
          conflicts
        end

        # Applies all non-conflicting changes from both sides and appends tail additions.
        def apply_changes(base_lines, ours_lines, theirs_lines, ours_changes, theirs_changes)
          merged = base_lines.dup

          # theirs_changes win when ours doesn't touch the same line (no conflict guard needed here)
          all_changes = ours_changes.merge(theirs_changes)
          all_changes.each { |idx, new_line| merged[idx] = new_line }

          # Append lines added at the end by either side
          if theirs_lines.length > base_lines.length && ours_lines.length == base_lines.length
            merged += theirs_lines[base_lines.length..]
          elsif ours_lines.length > base_lines.length && theirs_lines.length == base_lines.length
            merged += ours_lines[base_lines.length..]
          end

          merged
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/branches/merger_spec.rb
```

Expected: `7 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/branches/merger.rb spec/docsmith/branches/merger_spec.rb
git commit -m "feat(branches): add Branches::Merger with fast-forward and three-way merge

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 4.4 — `VersionManager#save!` branch support

**Files:**
- Modify: `lib/docsmith/version_manager.rb`
- Test: append to `spec/docsmith/version_manager_spec.rb`

- [ ] **Step 1: Write the failing test** (append inside the existing `RSpec.describe Docsmith::VersionManager` block)

```ruby
describe ".save! with branch:" do
  include FactoryBot::Syntax::Methods

  let(:user)   { create(:user) }
  let(:doc)    { create(:document, content: "initial", content_type: "markdown") }

  let(:branch) do
    v1 = Docsmith::VersionManager.save!(doc, author: user)
    Docsmith::Branches::Branch.create!(
      document:       doc,
      name:           "feature",
      source_version: v1,
      author:         user,
      status:         "active"
    )
  end

  it "sets branch_id on the created DocumentVersion" do
    doc.update_columns(content: "branch content")
    version = Docsmith::VersionManager.save!(doc, author: user, branch: branch)
    expect(version.branch_id).to eq(branch.id)
  end

  it "updates branch head_version_id to the new version" do
    doc.update_columns(content: "branch content")
    version = Docsmith::VersionManager.save!(doc, author: user, branch: branch)
    expect(branch.reload.head_version_id).to eq(version.id)
  end

  it "returns nil when content is unchanged" do
    # branch content same as latest version
    result = Docsmith::VersionManager.save!(doc, author: user, branch: branch)
    expect(result).to be_nil
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/version_manager_spec.rb
```

Expected: `ArgumentError: unknown keyword: branch` or test fails on branch_id not found.

- [ ] **Step 3: Update VersionManager#save!** (add `branch:` keyword throughout)

In `lib/docsmith/version_manager.rb`, update the `save!` class method signature and body:

```ruby
# Creates a new DocumentVersion snapshot for the given document.
#
# @param document [Docsmith::Document]
# @param author [Object]
# @param summary [String, nil]
# @param branch [Docsmith::Branches::Branch, nil] set to create a branch version
# @return [Docsmith::DocumentVersion, nil] nil if content is unchanged
def self.save!(document, author:, summary: nil, branch: nil)
  latest  = document.versions.order(version_number: :desc).first
  content = document.content.to_s

  return nil if latest && latest.content == content

  prune_if_needed!(document)

  number = (latest&.version_number || 0) + 1

  version = Docsmith::DocumentVersion.create!(
    document:       document,
    version_number: number,
    content:        content,
    content_type:   document.content_type,
    author:         author,
    change_summary: summary,
    branch_id:      branch&.id
  )

  document.update_columns(versions_count: number, last_versioned_at: Time.current)
  branch&.update_columns(head_version_id: version.id)

  fire_event(:version_created, document: document, version: version, author: author)
  version
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/version_manager_spec.rb
```

Expected: all examples pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/version_manager.rb spec/docsmith/version_manager_spec.rb
git commit -m "feat(branches): support branch: option in VersionManager#save!

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 4.5 — `Branches::Manager` (create! + merge!)

**Files:**
- Create: `lib/docsmith/branches/manager.rb`
- Create: `spec/docsmith/branches/manager_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/docsmith/branches/manager_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Branches::Manager do
  include FactoryBot::Syntax::Methods

  let(:user) { create(:user) }
  let(:doc)  { create(:document, content: "line one\nline two\nline three", content_type: "markdown") }
  let!(:v1)  { Docsmith::VersionManager.save!(doc, author: user) }

  describe ".create!" do
    it "creates a Branch forked from the given version" do
      branch = described_class.create!(doc, name: "feature", from_version: 1, author: user)
      expect(branch).to be_a(Docsmith::Branches::Branch)
      expect(branch.source_version).to eq(v1)
      expect(branch.status).to eq("active")
    end

    it "fires :branch_created hook with branch payload" do
      fired = []
      Docsmith.configuration.on(:branch_created) { |e| fired << e }
      described_class.create!(doc, name: "feature", from_version: 1, author: user)
      expect(fired.length).to eq(1)
      expect(fired.first.branch.name).to eq("feature")
    end

    it "emits branch_created.docsmith AS::Notifications event" do
      received = []
      sub = ActiveSupport::Notifications.subscribe("branch_created.docsmith") { |*args| received << args }
      described_class.create!(doc, name: "feature", from_version: 1, author: user)
      ActiveSupport::Notifications.unsubscribe(sub)
      expect(received).not_to be_empty
    end

    it "raises ActiveRecord::RecordNotFound for unknown version" do
      expect {
        described_class.create!(doc, name: "b", from_version: 99, author: user)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe ".merge!" do
    let(:branch) { described_class.create!(doc, name: "feature", from_version: 1, author: user) }

    context "fast-forward merge (main unchanged since fork)" do
      before do
        doc.update_columns(content: "line one\nline two\nline three\nline four")
        Docsmith::VersionManager.save!(doc, author: user, branch: branch)
      end

      it "returns a successful MergeResult" do
        result = described_class.merge!(doc, branch: branch, author: user)
        expect(result).to be_a(Docsmith::MergeResult)
        expect(result.success?).to be(true)
      end

      it "merged_version has branch content and no branch_id" do
        result = described_class.merge!(doc, branch: branch, author: user)
        expect(result.merged_version.content).to include("line four")
        expect(result.merged_version.branch_id).to be_nil
      end

      it "marks the branch as merged" do
        described_class.merge!(doc, branch: branch, author: user)
        expect(branch.reload.status).to eq("merged")
      end

      it "fires :branch_merged hook" do
        fired = []
        Docsmith.configuration.on(:branch_merged) { |e| fired << e }
        described_class.merge!(doc, branch: branch, author: user)
        expect(fired.length).to eq(1)
      end
    end

    context "merge with conflicts" do
      before do
        # Branch edits line 2
        doc.update_columns(content: "line one\nBRANCH EDIT\nline three")
        Docsmith::VersionManager.save!(doc, author: user, branch: branch)
        # Main also edits line 2 differently
        doc.update_columns(content: "line one\nMAIN EDIT\nline three")
        Docsmith::VersionManager.save!(doc, author: user)
      end

      it "returns unsuccessful MergeResult with conflicts" do
        result = described_class.merge!(doc, branch: branch, author: user)
        expect(result.success?).to be(false)
        expect(result.conflicts).not_to be_empty
      end

      it "does not create a new version on main" do
        versions_before = doc.versions.where(branch_id: nil).count
        described_class.merge!(doc, branch: branch, author: user)
        expect(doc.versions.where(branch_id: nil).count).to eq(versions_before)
      end

      it "fires :merge_conflict hook" do
        fired = []
        Docsmith.configuration.on(:merge_conflict) { |e| fired << e }
        described_class.merge!(doc, branch: branch, author: user)
        expect(fired.length).to eq(1)
      end
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/branches/manager_spec.rb
```

Expected: `NameError: uninitialized constant Docsmith::Branches::Manager`

- [ ] **Step 3: Implement**

```ruby
# lib/docsmith/branches/manager.rb
# frozen_string_literal: true

module Docsmith
  module Branches
    # Service object for creating and merging document branches.
    class Manager
      class << self
        # Creates a new Branch forked from a specific version of the document.
        #
        # @param document [Docsmith::Document]
        # @param name [String]
        # @param from_version [Integer] version_number to fork from
        # @param author [Object]
        # @return [Docsmith::Branches::Branch]
        # @raise [ActiveRecord::RecordNotFound] if from_version does not exist
        def create!(document, name:, from_version:, author:)
          source = Docsmith::DocumentVersion.find_by!(document: document, version_number: from_version)

          branch = Branch.create!(
            document:       document,
            name:           name,
            source_version: source,
            author:         author,
            status:         "active"
          )

          fire_event(:branch_created, document: document, version: source, author: author, branch: branch)
          branch
        end

        # Merges a branch into the main document history.
        # Attempts fast-forward first, then three-way merge.
        # On success: creates new main version and marks branch merged.
        # On conflict: fires merge_conflict event; no version created.
        #
        # @param document [Docsmith::Document]
        # @param branch [Docsmith::Branches::Branch]
        # @param author [Object]
        # @return [Docsmith::MergeResult]
        def merge!(document, branch:, author:)
          branch_head = branch.head_version || branch.source_version
          source      = branch.source_version
          main_head   = document.versions.where(branch_id: nil).order(version_number: :desc).first!

          internal = Merger.merge(source_version: source, branch_head: branch_head, main_head: main_head)

          unless internal.success?
            result = MergeResult.new(merged_version: nil, conflicts: internal.conflicts)
            fire_event(:merge_conflict, document: document, version: main_head, author: author,
                       branch: branch, merge_result: result)
            return result
          end

          document.update_columns(content: internal.merged_content)
          new_version = VersionManager.save!(document, author: author, summary: "Merge branch '#{branch.name}'")
          branch.update_columns(status: "merged", merged_at: Time.current)

          result = MergeResult.new(merged_version: new_version, conflicts: [])
          fire_event(:branch_merged, document: document, version: new_version, author: author,
                     branch: branch, merge_result: result)
          result
        end

        private

        def fire_event(name, document:, version:, author:, branch:, merge_result: nil)
          event = Events::Event.new(
            name:         name,
            record:       document.subject || document,
            document:     document,
            version:      version,
            author:       author,
            branch:       branch,
            merge_result: merge_result
          )
          Events::HookRegistry.fire(name, event)
          Events::Notifier.instrument("#{name}.docsmith", event)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/branches/manager_spec.rb
```

Expected: `11 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/branches/manager.rb spec/docsmith/branches/manager_spec.rb
git commit -m "feat(branches): add Branches::Manager with create! and merge!

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 4.6 — Versionable branch methods

**Files:**
- Modify: `lib/docsmith/versionable.rb`
- Test: append to `spec/docsmith/versionable_spec.rb`

- [ ] **Step 1: Write the failing tests** (append inside the existing `RSpec.describe Docsmith::Versionable` block)

```ruby
describe "#save_version! with branch:" do
  include FactoryBot::Syntax::Methods

  let(:article) { create(:article, body: "initial") }
  let(:user)    { create(:user) }
  let(:branch) do
    article.save_version!(author: user)
    article.create_branch!(name: "feature", from_version: 1, author: user)
  end

  it "creates a version with branch_id set" do
    article.body = "branch content"
    article.save!
    version = article.save_version!(author: user, branch: branch)
    expect(version.branch_id).to eq(branch.id)
  end
end

describe "#create_branch!" do
  include FactoryBot::Syntax::Methods

  let(:article) { create(:article, body: "initial content") }
  let(:user)    { create(:user) }

  before { article.save_version!(author: user) }

  it "creates a Branch from the given version" do
    branch = article.create_branch!(name: "feature", from_version: 1, author: user)
    expect(branch).to be_a(Docsmith::Branches::Branch)
    expect(branch.name).to eq("feature")
    expect(branch.status).to eq("active")
  end
end

describe "#branches and #active_branches" do
  include FactoryBot::Syntax::Methods

  let(:article) { create(:article, body: "content") }
  let(:user)    { create(:user) }

  before do
    article.save_version!(author: user)
    article.create_branch!(name: "feature", from_version: 1, author: user)
    article.create_branch!(name: "hotfix",  from_version: 1, author: user)
  end

  it "#branches returns all branches" do
    expect(article.branches.count).to eq(2)
  end

  it "#active_branches returns only active branches" do
    expect(article.active_branches.count).to eq(2)
  end
end

describe "#merge_branch!" do
  include FactoryBot::Syntax::Methods

  let(:article) { create(:article, body: "line one\nline two\nline three") }
  let(:user)    { create(:user) }
  let(:branch) do
    article.save_version!(author: user)
    article.create_branch!(name: "feature", from_version: 1, author: user)
  end

  before do
    article.body = "line one\nline two\nline three\nline four"
    article.save!
    article.save_version!(author: user, branch: branch)
  end

  it "returns a MergeResult" do
    result = article.merge_branch!(branch, author: user)
    expect(result).to be_a(Docsmith::MergeResult)
  end

  it "fast-forward merges successfully and new version has branch content" do
    result = article.merge_branch!(branch, author: user)
    expect(result.success?).to be(true)
    expect(result.merged_version.content).to include("line four")
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb
```

Expected: `NoMethodError: undefined method 'create_branch!'`

- [ ] **Step 3: Add methods to Versionable**

Update the existing `save_version!` method to accept `branch:`:

```ruby
# Creates a new DocumentVersion snapshot.
#
# @param author [Object]
# @param summary [String, nil]
# @param branch [Docsmith::Branches::Branch, nil]
# @return [Docsmith::DocumentVersion, nil] nil if content is unchanged
def save_version!(author:, summary: nil, branch: nil)
  _sync_docsmith_content!
  VersionManager.save!(_docsmith_document, author: author, summary: summary, branch: branch)
end
```

Add the new branch methods (inside the public instance methods section):

```ruby
# Creates a new Branch forked from a specific version of this document.
#
# @param name [String]
# @param from_version [Integer] version_number to fork from
# @param author [Object]
# @return [Docsmith::Branches::Branch]
def create_branch!(name:, from_version:, author:)
  Branches::Manager.create!(_docsmith_document, name: name, from_version: from_version, author: author)
end

# Returns all branches for this document.
#
# @return [ActiveRecord::Relation<Docsmith::Branches::Branch>]
def branches
  Branches::Branch.where(document: _docsmith_document)
end

# Returns only active branches for this document.
#
# @return [ActiveRecord::Relation<Docsmith::Branches::Branch>]
def active_branches
  branches.active
end

# Merges a branch into the main document history.
#
# @param branch [Docsmith::Branches::Branch]
# @param author [Object]
# @return [Docsmith::MergeResult]
def merge_branch!(branch, author:)
  Branches::Manager.merge!(_docsmith_document, branch: branch, author: author)
end
```

- [ ] **Step 4: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/versionable_spec.rb
```

Expected: all examples pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith/versionable.rb spec/docsmith/versionable_spec.rb
git commit -m "feat(branches): add Versionable branch methods (create_branch!, branches, merge_branch!)

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

### Task 4.7 — Wire Phase 4 requires + integration test

**Files:**
- Modify: `lib/docsmith.rb`
- Create: `spec/docsmith/phase4_integration_spec.rb`

- [ ] **Step 1: Add Phase 4 requires to `lib/docsmith.rb`** (after Phase 3 requires)

```ruby
require_relative "docsmith/merge_result"
require_relative "docsmith/branches/branch"
require_relative "docsmith/branches/merger"
require_relative "docsmith/branches/manager"
```

- [ ] **Step 2: Write the failing integration test**

```ruby
# spec/docsmith/phase4_integration_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Phase 4: Branching & Merging integration" do
  include FactoryBot::Syntax::Methods

  let(:user)    { create(:user) }
  let(:article) { create(:article, body: "line one\nline two\nline three") }

  before { article.save_version!(author: user) }

  it "fast-forward merge lifecycle: create branch, add version, merge" do
    branch = article.create_branch!(name: "feature", from_version: 1, author: user)
    expect(branch.status).to eq("active")

    article.body = "line one\nline two\nline three\nline four"
    article.save!
    article.save_version!(author: user, branch: branch)

    result = article.merge_branch!(branch, author: user)
    expect(result.success?).to be(true)
    expect(result.merged_version.content).to include("line four")
    expect(result.merged_version.branch_id).to be_nil
    expect(branch.reload.status).to eq("merged")
  end

  it "lists active branches" do
    article.create_branch!(name: "feat-a", from_version: 1, author: user)
    article.create_branch!(name: "feat-b", from_version: 1, author: user)
    expect(article.active_branches.count).to eq(2)
  end

  it "returns conflict result when both sides edit the same line" do
    branch = article.create_branch!(name: "feature", from_version: 1, author: user)

    article.body = "line one\nBRANCH EDIT\nline three"
    article.save!
    article.save_version!(author: user, branch: branch)

    article.body = "line one\nMAIN EDIT\nline three"
    article.save!
    article.save_version!(author: user)

    result = article.merge_branch!(branch, author: user)
    expect(result.success?).to be(false)
    expect(result.conflicts.first[:line]).to eq(2)
  end

  it "Branch#diff_from_source returns a Diff::Result" do
    branch = article.create_branch!(name: "feature", from_version: 1, author: user)
    article.body = "line one\nline two\nline three\nline four"
    article.save!
    article.save_version!(author: user, branch: branch)

    diff = branch.diff_from_source
    expect(diff).to be_a(Docsmith::Diff::Result)
    expect(diff.additions).to eq(1)
  end

  it "fires :branch_created and :branch_merged hooks" do
    created_events = []
    merged_events  = []
    Docsmith.configuration.on(:branch_created) { |e| created_events << e }
    Docsmith.configuration.on(:branch_merged)  { |e| merged_events  << e }

    branch = article.create_branch!(name: "feature", from_version: 1, author: user)
    article.body = "line one\nline two\nline three\nline four"
    article.save!
    article.save_version!(author: user, branch: branch)
    article.merge_branch!(branch, author: user)

    expect(created_events.length).to eq(1)
    expect(merged_events.length).to eq(1)
  end
end
```

- [ ] **Step 3: Run — expect PASS**

```bash
bundle exec rspec spec/docsmith/phase4_integration_spec.rb
```

Expected: `5 examples, 0 failures`

- [ ] **Step 4: Run the full suite**

```bash
bundle exec rspec spec/
```

Expected: all examples pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/docsmith.rb spec/docsmith/phase4_integration_spec.rb
git commit -m "feat(branches): wire Phase 4 requires and add integration test

Co-authored-by: Swastik <swastik.thapaliya@gmail.com>"
```

---

**Phase 4 complete.** All four phases implemented and tested.
Run `bundle exec rspec spec/` to confirm the full suite is green.

---

## Execution

**Plan complete and saved to `docs/superpowers/plans/2026-04-01-docsmith-full-plan.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
