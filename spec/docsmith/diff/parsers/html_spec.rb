# frozen_string_literal: true

require "spec_helper"
require "docsmith/diff/parsers/html"

RSpec.describe Docsmith::Diff::Parsers::Html do
  subject(:parser) { described_class.new }

  describe "#tokenize" do
    it "treats each tag as one atomic token, with start offsets" do
      expect(parser.tokenize("<p>Hi</p>"))
        .to eq([["<p>", 0], ["Hi", 3], ["</p>", 5]])
    end

    it "keeps a tag with attributes as a single token" do
      expect(parser.tokenize('<div class="foo bar">x</div>').map(&:first))
        .to eq(['<div class="foo bar">', "x", "</div>"])
    end

    it "never emits bare angle brackets as tokens" do
      expect(parser.tokenize("<p>a</p>").map(&:first)).not_to include("<", ">")
    end
  end

  describe "#compute" do
    it "reports a changed tag pair as replaces carrying both sides" do
      edits = parser.compute("<p>Hello</p>", "<span>Hello</span>")

      expect(edits.map { |e| [e[:old][:text], e[:new][:text]] })
        .to eq([["<p>", "<span>"], ["</p>", "</span>"]])
    end

    # Previously three separate entries: "<p>", "World", "</p>".
    it "collapses an added paragraph into a single insert" do
      edits = parser.compute("<p>Hello</p>", "<p>Hello</p><p>World</p>")

      expect(edits.length).to eq(1)
      expect(edits.first[:type]).to eq(:insert)
      expect(edits.first[:new][:text]).to eq("<p>World</p>")
    end

    it "detects a word change inside a tag" do
      edits = parser.compute("<p>Hello world</p>", "<p>Hello Ruby</p>")

      expect(edits.first[:type]).to eq(:replace)
      expect(edits.first[:old][:text]).to eq("world")
      expect(edits.first[:new][:text]).to eq("Ruby")
    end

    it "treats a tag with attributes as one atomic unit when it changes" do
      edits = parser.compute('<div class="foo">bar</div>', '<div class="baz">bar</div>')

      expect(edits.first[:old][:text]).to eq('<div class="foo">')
      expect(edits.first[:new][:text]).to eq('<div class="baz">')
    end

    it "returns empty array for identical HTML" do
      html = "<p>Same content</p>"
      expect(parser.compute(html, html)).to be_empty
    end

    # The payload that prompted this redesign: a heading rewrite produced seven
    # entries whose "line" values ran to 7 in a three-line document.
    it "collapses a heading rewrite into a single replace with real line numbers" do
      old_content = "my document\n\nsecond para"
      new_content = "<h1>this is a new heading</h1>\n\nsecond para"
      edits = parser.compute(old_content, new_content)

      expect(edits.length).to eq(1)
      expect(edits.first).to include(type: :replace)
      expect(edits.first[:old]).to include(start: 0, end: 11, line: 1, column: 1, text: "my document")
      expect(edits.first[:new]).to include(
        start: 0, end: 30, line: 1, column: 1, text: "<h1>this is a new heading</h1>"
      )
      expect(edits.map { |e| e[:new][:line] }.max).to be <= new_content.lines.size
    end
  end
end
