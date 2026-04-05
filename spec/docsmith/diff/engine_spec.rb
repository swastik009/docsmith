# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Diff::Engine do
  include FactoryBot::Syntax::Methods

  let(:doc) { create(:document, content: "line one\nline two", content_type: "markdown") }
  let(:v1)  { create(:document_version, document: doc, content: "line one\nline two", version_number: 1, content_type: "markdown") }
  let(:v2)  { create(:document_version, document: doc, content: "line one\nline two\nline three", version_number: 2, content_type: "markdown") }

  describe ".between" do
    subject(:result) { described_class.between(v1, v2) }

    it "returns a Diff::Result" do
      expect(result).to be_a(Docsmith::Diff::Result)
    end

    it "sets content_type from the from-version" do
      expect(result.content_type).to eq("markdown")
    end

    it "sets from_version and to_version from the version numbers" do
      expect(result.from_version).to eq(1)
      expect(result.to_version).to eq(2)
    end

    it "detects the added line" do
      expect(result.additions).to eq(1)
      expect(result.deletions).to eq(0)
    end
  end

  describe "Docsmith::Diff.between (module convenience method)" do
    it "delegates to Engine.between and returns a Result" do
      result = Docsmith::Diff.between(v1, v2)
      expect(result).to be_a(Docsmith::Diff::Result)
      expect(result.additions).to eq(1)
    end
  end
end
