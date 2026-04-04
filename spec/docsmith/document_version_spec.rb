# frozen_string_literal: true

RSpec.describe Docsmith::DocumentVersion do
  let(:doc)  { create(:docsmith_document) }
  let(:user) { create(:user) }

  describe "table name" do
    it { expect(described_class.table_name).to eq("docsmith_versions") }
  end

  describe "validations" do
    it "requires version_number" do
      v = described_class.new(document: doc, content: "x", content_type: "markdown")
      expect(v).not_to be_valid
    end

    it "requires content" do
      v = described_class.new(document: doc, version_number: 1, content_type: "markdown")
      expect(v).not_to be_valid
    end

    it "requires unique version_number per document" do
      described_class.create!(document: doc, version_number: 1, content: "v1",
                               content_type: "markdown", created_at: Time.current)
      dup = described_class.new(document: doc, version_number: 1, content: "v2",
                                content_type: "markdown")
      expect(dup).not_to be_valid
    end
  end

  describe "associations" do
    it "belongs to document" do
      v = described_class.new(document: doc, version_number: 1,
                              content: "hi", content_type: "markdown",
                              created_at: Time.current)
      expect(v.document).to eq(doc)
    end
  end

  describe "#previous_version" do
    it "returns nil for the first version" do
      v1 = described_class.create!(document: doc, version_number: 1, content: "v1",
                                   content_type: "markdown", created_at: Time.current)
      expect(v1.previous_version).to be_nil
    end

    it "returns v1 when called on v2" do
      v1 = described_class.create!(document: doc, version_number: 1, content: "v1",
                                   content_type: "markdown", created_at: Time.current)
      v2 = described_class.create!(document: doc, version_number: 2, content: "v2",
                                   content_type: "markdown", created_at: Time.current)
      expect(v2.previous_version).to eq(v1)
    end
  end
end
