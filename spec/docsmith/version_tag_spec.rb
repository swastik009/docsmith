# frozen_string_literal: true

RSpec.describe Docsmith::VersionTag do
  let(:doc)  { create(:docsmith_document) }
  let(:ver)  do
    Docsmith::DocumentVersion.create!(
      document: doc, version_number: 1, content: "v1",
      content_type: "markdown", created_at: Time.current
    )
  end

  describe "table name" do
    it { expect(described_class.table_name).to eq("docsmith_version_tags") }
  end

  describe "validations" do
    it "requires name" do
      tag = described_class.new(document: doc, version: ver)
      expect(tag).not_to be_valid
    end

    it "enforces tag name uniqueness per document (not per version)" do
      described_class.create!(document: doc, version: ver, name: "v1.0",
                               created_at: Time.current)
      dup = described_class.new(document: doc, version: ver, name: "v1.0")
      expect(dup).not_to be_valid
    end

    it "allows same tag name on different documents" do
      doc2 = create(:docsmith_document)
      ver2 = Docsmith::DocumentVersion.create!(
        document: doc2, version_number: 1, content: "v1",
        content_type: "markdown", created_at: Time.current
      )
      described_class.create!(document: doc, version: ver, name: "v1.0",
                               created_at: Time.current)
      tag2 = described_class.new(document: doc2, version: ver2, name: "v1.0")
      expect(tag2).to be_valid
    end
  end
end
