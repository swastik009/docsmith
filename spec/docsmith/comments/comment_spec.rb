# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Comments::Comment do
  include FactoryBot::Syntax::Methods

  let(:user)    { create(:user) }
  let(:doc)     { create(:document, content: "hello", content_type: "markdown") }
  let(:version) { create(:document_version, document: doc, content: "hello", version_number: 1, content_type: "markdown") }

  describe "associations" do
    it "belongs to a version" do
      comment = described_class.create!(
        version: version, author: user, body: "nice",
        anchor_type: "document", anchor_data: {}
      )
      expect(comment.version).to eq(version)
    end

    it "supports threaded replies via parent/replies" do
      parent = described_class.create!(
        version: version, author: user, body: "parent",
        anchor_type: "document", anchor_data: {}
      )
      reply = described_class.create!(
        version: version, author: user, body: "reply", parent: parent,
        anchor_type: "document", anchor_data: {}
      )
      expect(reply.parent).to eq(parent)
      expect(parent.replies).to include(reply)
    end
  end

  describe "validations" do
    it "requires body" do
      comment = described_class.new(version: version, author: user, anchor_type: "document", anchor_data: {})
      expect(comment).not_to be_valid
      expect(comment.errors[:body]).not_to be_empty
    end

    it "requires anchor_type to be document or range" do
      comment = described_class.new(
        version: version, author: user, body: "text",
        anchor_type: "invalid", anchor_data: {}
      )
      expect(comment).not_to be_valid
    end
  end

  describe "scopes" do
    let!(:root1) { described_class.create!(version: version, author: user, body: "root1", anchor_type: "document", anchor_data: {}) }
    let!(:root2) { described_class.create!(version: version, author: user, body: "root2", anchor_type: "document", anchor_data: {}) }
    let!(:reply) { described_class.create!(version: version, author: user, body: "reply", anchor_type: "document", anchor_data: {}, parent: root1) }

    it ".top_level returns only root-level comments" do
      expect(described_class.top_level.to_a).to contain_exactly(root1, root2)
    end

    it ".unresolved returns only unresolved comments" do
      expect(described_class.unresolved.count).to eq(3)
    end

    it ".document_level returns only document anchor type" do
      described_class.create!(version: version, author: user, body: "range", anchor_type: "range", anchor_data: { start_offset: 0, end_offset: 1 }.to_json)
      expect(described_class.document_level.count).to eq(3)
      expect(described_class.range_anchored.count).to eq(1)
    end
  end

  describe "#anchor_data accessor" do
    it "accepts a Hash and returns a Hash" do
      comment = described_class.create!(
        version: version, author: user, body: "note",
        anchor_type: "document", anchor_data: { foo: "bar" }
      )
      expect(comment.anchor_data).to be_a(Hash)
    end
  end
end
