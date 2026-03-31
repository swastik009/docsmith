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
