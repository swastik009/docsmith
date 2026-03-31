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
