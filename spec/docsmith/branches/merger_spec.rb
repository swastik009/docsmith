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
