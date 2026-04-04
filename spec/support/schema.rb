# frozen_string_literal: true

# In-memory SQLite schema for tests.
# Mirrors db/migrate/create_docsmith_tables.rb with two intentional differences:
#   1. :jsonb columns use :text here (SQLite has no jsonb type)
#   2. Foreign key constraints are omitted (SQLite does not enforce them)
# Production migration uses :jsonb and add_foreign_key for PostgreSQL.

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
  add_index :docsmith_version_tags, %i[version_id]

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
