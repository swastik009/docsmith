# frozen_string_literal: true

RSpec.describe Docsmith::AutoSave do
  let(:doc)    { create(:docsmith_document, content: "hello") }
  let(:config) { { debounce: 30, auto_save: true, max_versions: nil, content_extractor: nil } }

  describe ".within_debounce?" do
    it "returns false when last_versioned_at is nil" do
      doc.update_column(:last_versioned_at, nil)
      expect(described_class.within_debounce?(doc, config)).to eq(false)
    end

    it "returns true when last saved less than debounce seconds ago" do
      doc.update_column(:last_versioned_at, 10.seconds.ago)
      expect(described_class.within_debounce?(doc, config)).to eq(true)
    end

    it "returns false when last saved more than debounce seconds ago" do
      doc.update_column(:last_versioned_at, 60.seconds.ago)
      expect(described_class.within_debounce?(doc, config)).to eq(false)
    end

    it "normalizes Duration debounce to integer" do
      config_with_duration = config.merge(debounce: 30.seconds)
      doc.update_column(:last_versioned_at, 10.seconds.ago)
      expect(described_class.within_debounce?(doc, config_with_duration)).to eq(true)
    end
  end

  describe ".call" do
    it "returns nil when within debounce window" do
      doc.update_column(:last_versioned_at, 5.seconds.ago)
      result = described_class.call(doc, author: nil, config: config)
      expect(result).to be_nil
    end

    it "delegates to VersionManager.save! outside debounce window" do
      doc.update_column(:last_versioned_at, 60.seconds.ago)
      expect(Docsmith::VersionManager).to receive(:save!).with(doc, author: nil, config: config)
      described_class.call(doc, author: nil, config: config)
    end
  end
end
