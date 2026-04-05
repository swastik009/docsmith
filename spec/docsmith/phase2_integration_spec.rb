# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Phase 2: Diff & Rendering integration" do
  include FactoryBot::Syntax::Methods

  let(:user)    { create(:user) }
  let(:article) { create(:article, body: "line one\nline two") }

  before do
    allow(Article).to receive(:docsmith_resolved_config).and_return(
      { content_field: :body, content_type: :markdown, auto_save: false, debounce: 30, max_versions: nil, content_extractor: nil }
    )
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
