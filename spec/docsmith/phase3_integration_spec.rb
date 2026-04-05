# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Phase 3: Comments & Inline Annotations integration" do
  include FactoryBot::Syntax::Methods

  let(:user)    { create(:user) }
  let(:article) { create(:article, body: "hello world content here for testing") }

  before do
    allow(Article).to receive(:docsmith_resolved_config).and_return(
      { content_field: :body, content_type: :markdown, auto_save: false, debounce: 30, max_versions: nil, content_extractor: nil }
    )
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
