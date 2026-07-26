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

    it "reports an added line as one insert (word-level for markdown)" do
      # v1: "line one\nline two"  →  v2 appends "\nline three".
      # The three added tokens ("\n", "line", "three") are one contiguous run,
      # so they collapse into a single edit.
      expect(result.stats).to eq(
        "insertions" => 1, "deletions" => 0, "replacements" => 0, "total" => 1
      )
      expect(result.changes.first[:new][:text]).to eq("\nline three")
    end
  end

  describe "Docsmith::Diff.between (module convenience method)" do
    it "delegates to Engine.between and returns a Result" do
      result = Docsmith::Diff.between(v1, v2)
      expect(result).to be_a(Docsmith::Diff::Result)
      expect(result.insertions).to eq(1)
    end
  end

  describe "format-aware parser dispatch" do
    let(:md_doc)   { create(:document, content: "# Hello", content_type: "markdown") }
    let(:html_doc) { create(:document, content: "<p>Hello</p>", content_type: "html") }

    let(:md_v1) do
      create(:document_version, document: md_doc, content: "Hello world",
             version_number: 1, content_type: "markdown")
    end
    let(:md_v2) do
      create(:document_version, document: md_doc, content: "Hello Ruby world",
             version_number: 2, content_type: "markdown")
    end

    let(:html_v1) do
      create(:document_version, document: html_doc, content: "<p>Hello</p>",
             version_number: 1, content_type: "html")
    end
    let(:html_v2) do
      create(:document_version, document: html_doc, content: "<p>Hello</p><p>World</p>",
             version_number: 2, content_type: "html")
    end

    it "uses Markdown parser for markdown content — detects word addition" do
      result = described_class.between(md_v1, md_v2)
      # "Hello world" → "Hello Ruby world": one word inserted
      expect(result.insertions).to eq(1)
      expect(result.changes.first[:new][:text]).to eq("Ruby")
    end

    it "uses HTML parser for html content — treats tags as atomic tokens" do
      result = described_class.between(html_v1, html_v2)
      # "<p>Hello</p>" → "<p>Hello</p><p>World</p>": one inserted paragraph,
      # reported as a single edit rather than three token additions.
      expect(result.insertions).to eq(1)
      expect(result.changes.first[:new][:text]).to eq("<p>World</p>")
    end
  end
end
