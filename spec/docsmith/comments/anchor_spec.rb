# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Comments::Anchor do
  let(:content) { "The quick brown fox jumps over the lazy dog" }

  describe ".build" do
    subject(:anchor) { described_class.build(content, start_offset: 4, end_offset: 9) }

    it "captures the anchored text" do
      expect(anchor[:anchored_text]).to eq("quick")
    end

    it "stores start and end offsets" do
      expect(anchor[:start_offset]).to eq(4)
      expect(anchor[:end_offset]).to eq(9)
    end

    it "sets status to active" do
      expect(anchor[:status]).to eq(Docsmith::Comments::Anchor::ACTIVE)
    end

    it "stores a SHA256 content_hash of the anchored text" do
      require "digest"
      expect(anchor[:content_hash]).to eq(Digest::SHA256.hexdigest("quick"))
    end
  end

  describe ".migrate" do
    let(:original_anchor) do
      described_class.build(content, start_offset: 4, end_offset: 9)
                     .transform_keys(&:to_s)  # simulate string-keyed JSON round-trip
    end

    context "when anchored text is at the exact same offset in the new content" do
      it "returns active status" do
        result = described_class.migrate(content, original_anchor)
        expect(result["status"]).to eq(Docsmith::Comments::Anchor::ACTIVE)
      end
    end

    context "when anchored text has moved but still exists" do
      let(:new_content) { "A quick brown fox jumps over the lazy dog" }

      it "returns drifted status with updated offsets" do
        result = described_class.migrate(new_content, original_anchor)
        expect(result["status"]).to eq(Docsmith::Comments::Anchor::DRIFTED)
        expect(result["start_offset"]).to eq(new_content.index("quick"))
      end
    end

    context "when anchored text no longer exists" do
      let(:new_content) { "Completely different content here" }

      it "returns orphaned status" do
        result = described_class.migrate(new_content, original_anchor)
        expect(result["status"]).to eq(Docsmith::Comments::Anchor::ORPHANED)
      end
    end
  end
end
