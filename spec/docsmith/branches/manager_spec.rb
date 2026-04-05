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
        doc.update_columns(content: "line one\nBRANCH EDIT\nline three")
        Docsmith::VersionManager.save!(doc, author: user, branch: branch)
        doc.update_columns(content: "line one\nMAIN EDIT\nline three")
        Docsmith::VersionManager.save!(doc, author: user)
      end

      it "returns unsuccessful MergeResult with conflicts" do
        result = described_class.merge!(doc, branch: branch, author: user)
        expect(result.success?).to be(false)
        expect(result.conflicts).not_to be_empty
      end

      it "does not create a new version on main" do
        versions_before = doc.document_versions.where(branch_id: nil).count
        described_class.merge!(doc, branch: branch, author: user)
        expect(doc.document_versions.where(branch_id: nil).count).to eq(versions_before)
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
