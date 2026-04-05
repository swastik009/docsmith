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
