# frozen_string_literal: true

require "active_record"
require "sqlite3"

DB_PATH = File.expand_path("../docsmith_demo.sqlite3", __dir__)

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: DB_PATH
)

ActiveRecord::Schema.define do
  create_table :articles, force: false do |t|
    t.string  :title, null: false
    t.text    :body
    t.timestamps
  end unless ActiveRecord::Base.connection.table_exists?(:articles)

  # HTML-content documents, used to demonstrate config.html_sanitizer.
  create_table :pages, force: false do |t|
    t.string :title, null: false
    t.text   :body
    t.timestamps
  end unless ActiveRecord::Base.connection.table_exists?(:pages)

  create_table :users, force: false do |t|
    t.string :name, null: false
    t.timestamps
  end unless ActiveRecord::Base.connection.table_exists?(:users)

  create_table :docsmith_documents, force: false do |t|
    t.string   :title
    t.text     :content
    t.string   :content_type,       null: false, default: "markdown"
    t.integer  :versions_count,     null: false, default: 0
    t.datetime :last_versioned_at
    t.string   :subject_type
    t.bigint   :subject_id
    t.json     :metadata,           null: false, default: {}
    t.timestamps
  end unless ActiveRecord::Base.connection.table_exists?(:docsmith_documents)

  unless ActiveRecord::Base.connection.index_exists?(:docsmith_documents, %i[subject_type subject_id])
    add_index :docsmith_documents, %i[subject_type subject_id]
  end

  create_table :docsmith_versions, force: false do |t|
    t.bigint   :document_id,      null: false
    t.integer  :version_number,   null: false
    t.text     :content,          null: false
    t.string   :content_type,     null: false
    t.string   :author_type
    t.bigint   :author_id
    t.string   :change_summary
    t.json     :metadata,         null: false, default: {}
    t.datetime :created_at,       null: false
  end unless ActiveRecord::Base.connection.table_exists?(:docsmith_versions)

  create_table :docsmith_version_tags, force: false do |t|
    t.bigint   :document_id,   null: false
    t.bigint   :version_id,    null: false
    t.string   :name,          null: false
    t.string   :author_type
    t.bigint   :author_id
    t.datetime :created_at,    null: false
  end unless ActiveRecord::Base.connection.table_exists?(:docsmith_version_tags)

  unless ActiveRecord::Base.connection.index_exists?(:docsmith_version_tags, %i[document_id name])
    add_index :docsmith_version_tags, %i[document_id name], unique: true
  end

  create_table :docsmith_comments, force: false do |t|
    t.bigint   :version_id,        null: false
    t.bigint   :parent_id
    t.string   :author_type
    t.bigint   :author_id
    t.text     :body,              null: false
    t.string   :anchor_type,       null: false, default: "document"
    t.json     :anchor_data,       null: false, default: {}
    t.boolean  :resolved,          null: false, default: false
    t.string   :resolved_by_type
    t.bigint   :resolved_by_id
    t.datetime :resolved_at
    t.datetime :created_at,        null: false
    t.datetime :updated_at,        null: false
  end unless ActiveRecord::Base.connection.table_exists?(:docsmith_comments)

  # Migrate demo databases created before the :text -> :json column fix.
  # The create_table calls above are all guarded by table_exists?, so an existing
  # demo DB would otherwise keep its old :text columns and hand models a raw
  # String where they now expect a Hash.
  #
  # change_column rebuilds the table on SQLite and preserves every row; the
  # stored values are already JSON text, so they simply start casting to Hash.
  {
    docsmith_documents: :metadata,
    docsmith_versions:  :metadata,
    docsmith_comments:  :anchor_data
  }.each do |table, column|
    next unless ActiveRecord::Base.connection.table_exists?(table)

    info = ActiveRecord::Base.connection.columns(table.to_s).find { |c| c.name == column.to_s }
    next if info.nil? || info.type == :json

    change_column table, column, :json, null: false, default: {}
  end
end

# Seed a default user so we always have an author
class User < ActiveRecord::Base; end
User.find_or_create_by!(name: "Demo User")
