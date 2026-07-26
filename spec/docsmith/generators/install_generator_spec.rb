# frozen_string_literal: true

require "spec_helper"
require "English"
require "fileutils"
require "tmpdir"
require "generators/docsmith/install/install_generator"

# Exercises the real generator against a temp destination. This was previously
# untestable: railties is what provides "rails/generators", and it was not a
# development dependency, so the migration template had no coverage at all.
RSpec.describe Docsmith::Generators::InstallGenerator do
  around do |example|
    Dir.mktmpdir("docsmith-generator") do |dir|
      @destination = dir
      example.run
    end
  end

  attr_reader :destination

  def run_generator!
    described_class.start(["--quiet"], destination_root: destination, shell: Thor::Base.shell.new)
  end

  def migration_body
    path = Dir.glob(File.join(destination, "db/migrate/*create_docsmith_tables.rb")).first
    raise "no migration was generated in #{destination}" if path.nil?

    File.read(path)
  end

  def initializer_body
    File.read(File.join(destination, "config/initializers/docsmith.rb"))
  end

  it "generates a timestamped migration and an initializer" do
    run_generator!

    expect(Dir.glob(File.join(destination, "db/migrate/*create_docsmith_tables.rb")).length).to eq(1)
    expect(File).to exist(File.join(destination, "config/initializers/docsmith.rb"))
  end

  it "generates a syntactically valid migration" do
    run_generator!
    body = migration_body

    expect { RubyVM::InstructionSequence.compile(body) }.not_to raise_error
  end

  # The point of all of this: the generated migration has to actually run.
  # In 0.1.0 the generator crashed before writing anything, and the template it
  # would have written used t.jsonb, which SQLite cannot create.
  it "produces a migration that runs, creating usable tables" do
    run_generator!

    # Run it against a fresh database in a subprocess: the suite's own in-memory
    # DB already has these tables, and this proves a real app can migrate cleanly.
    migration_path = File.join(destination, "migration_under_test.rb")
    File.write(migration_path, migration_body)
    report_path = File.join(destination, "report.json")

    script = <<~RUBY
      require "active_record"
      require "sqlite3"
      require "json"
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      ActiveRecord::Migration.verbose = false
      load #{migration_path.inspect}
      CreateDocsmithTables.new.change
      conn = ActiveRecord::Base.connection
      File.write(#{report_path.inspect}, JSON.dump(
        tables:   conn.tables.grep(/^docsmith_/).sort,
        versions: conn.columns("docsmith_versions").to_h { |c| [c.name, c.type.to_s] },
        comments: conn.columns("docsmith_comments").to_h { |c| [c.name, c.type.to_s] }
      ))
    RUBY

    script_path = File.join(destination, "run_migration.rb")
    File.write(script_path, script)

    output = `bundle exec ruby #{script_path} 2>&1`
    expect($CHILD_STATUS).to be_success, "migration failed to run:\n#{output}"

    report = JSON.parse(File.read(report_path))
    expect(report["tables"]).to eq(
      %w[docsmith_comments docsmith_documents docsmith_version_tags docsmith_versions]
    )
    expect(report["versions"]["metadata"]).to eq("json")
    expect(report["versions"]["content"]).to eq("text")
    expect(report["comments"]["anchor_data"]).to eq("json")
  end

  it "creates all four tables" do
    run_generator!
    body = migration_body

    expect(body).to include("create_table :docsmith_documents")
    expect(body).to include("create_table :docsmith_versions")
    expect(body).to include("create_table :docsmith_version_tags")
    expect(body).to include("create_table :docsmith_comments")
  end

  describe "JSON column type per adapter" do
    it "emits :json on a non-PostgreSQL adapter" do
      # The suite runs on sqlite3, where t.jsonb does not exist — the old template
      # emitted jsonb unconditionally, so the generated migration could not run.
      run_generator!
      body = migration_body

      expect(body).to include("t.json")
      expect(body).not_to include("t.jsonb")
      expect(body.scan(/t\.json\s+:(metadata|anchor_data)/).flatten)
        .to contain_exactly("metadata", "metadata", "anchor_data")
    end

    it "emits :jsonb on PostgreSQL" do
      config = instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, adapter: "postgresql")
      allow(ActiveRecord::Base).to receive(:connection_db_config).and_return(config)

      run_generator!

      expect(migration_body).to include("t.jsonb")
    end

    it "emits :jsonb for PostgreSQL-derived adapters" do
      config = instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, adapter: "postgis")
      allow(ActiveRecord::Base).to receive(:connection_db_config).and_return(config)

      run_generator!

      expect(migration_body).to include("t.jsonb")
    end

    it "falls back to :json when the adapter cannot be determined" do
      allow(ActiveRecord::Base).to receive(:connection_db_config).and_raise(StandardError, "no config")

      run_generator!

      expect(migration_body).to include("t.json")
    end
  end

  describe "generated initializer" do
    it "documents html_sanitizer, since the default escapes html content" do
      run_generator!

      expect(initializer_body).to include("config.html_sanitizer")
      expect(initializer_body).to include(":unsafe_raw")
    end

    it "does not offer the removed diff_context_lines setting" do
      run_generator!

      expect(initializer_body).not_to include("diff_context_lines")
    end
  end
end
