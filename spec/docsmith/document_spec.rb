# frozen_string_literal: true

RSpec.describe Docsmith::Document do
  describe "table name" do
    it { expect(described_class.table_name).to eq("docsmith_documents") }
  end

  describe "associations" do
    it "has many document_versions" do
      doc = create(:docsmith_document)
      expect(doc).to respond_to(:document_versions)
    end
  end

  describe "validations" do
    it "requires content_type" do
      doc = build(:docsmith_document, content_type: nil)
      expect(doc).not_to be_valid
    end

    it "rejects unknown content_type" do
      doc = build(:docsmith_document, content_type: "pdf")
      expect(doc).not_to be_valid
    end

    it "accepts html, markdown, json" do
      %w[html markdown json].each do |ct|
        doc = build(:docsmith_document, content_type: ct)
        expect(doc).to be_valid
      end
    end
  end

  describe ".from_record" do
    let(:article) { create(:article) }

    it "creates a shadow document linked to the record" do
      doc = described_class.from_record(article)
      expect(doc).to be_persisted
      expect(doc.subject).to eq(article)
    end

    it "returns same document on second call (find-or-create)" do
      doc1 = described_class.from_record(article)
      doc2 = described_class.from_record(article)
      expect(doc1.id).to eq(doc2.id)
    end

    it "sets content_type to markdown by default" do
      doc = described_class.from_record(article)
      expect(doc.content_type).to eq("markdown")
    end

    it "uses the record's title if it responds to title" do
      doc = described_class.from_record(article)
      expect(doc.title).to eq(article.title)
    end
  end

  describe "#current_version" do
    it "returns nil when no versions exist" do
      doc = create(:docsmith_document)
      expect(doc.current_version).to be_nil
    end
  end
end
