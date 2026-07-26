# frozen_string_literal: true

require "spec_helper"
require "docsmith/diff/parsers/markdown"

RSpec.describe Docsmith::Diff::Parsers::Markdown do
  subject(:parser) { described_class.new }

  describe "#tokenize" do
    it "splits into words and newline runs, each with its start offset" do
      expect(parser.tokenize("Hello world\n\nFoo"))
        .to eq([["Hello", 0], ["world", 6], ["\n\n", 11], ["Foo", 13]])
    end

    it "treats a paragraph break as one token" do
      expect(parser.tokenize("a\n\n\nb").map(&:first)).to eq(["a", "\n\n\n", "b"])
    end
  end

  describe "#compute" do
    it "reports an inserted word as one insert" do
      edits = parser.compute("Hello world", "Hello Ruby world")

      expect(edits.length).to eq(1)
      expect(edits.first[:type]).to eq(:insert)
      expect(edits.first[:new][:text]).to eq("Ruby")
    end

    it "reports a deleted word as one delete" do
      edits = parser.compute("Hello Ruby world", "Hello world")

      expect(edits.first[:type]).to eq(:delete)
      expect(edits.first[:old][:text]).to eq("Ruby")
    end

    it "reports a changed word as a replace carrying both sides" do
      edits = parser.compute("Hello world", "Hello Ruby")

      expect(edits.first[:type]).to eq(:replace)
      expect(edits.first[:old][:text]).to eq("world")
      expect(edits.first[:new][:text]).to eq("Ruby")
    end

    it "returns empty array for identical content" do
      expect(parser.compute("same text", "same text")).to be_empty
    end

    # Previously this produced three separate entries ("\n", "line", "three")
    # because every token became its own change.
    it "collapses a whole added line into a single edit" do
      edits = parser.compute("line one\nline two", "line one\nline two\nline three")

      expect(edits.length).to eq(1)
      expect(edits.first[:type]).to eq(:insert)
      expect(edits.first[:new][:text]).to eq("\nline three")
    end

    it "collapses an added paragraph into a single edit" do
      edits = parser.compute("Para one", "Para one\n\nPara two")

      expect(edits.length).to eq(1)
      expect(edits.first[:new][:text]).to eq("\n\nPara two")
    end

    it "keeps separate word edits separate" do
      edits = parser.compute("the quick brown fox", "the slow brown wolf")

      expect(edits.length).to eq(2)
      expect(edits.map { |e| [e[:old][:text], e[:new][:text]] })
        .to eq([%w[quick slow], %w[fox wolf]])
    end

    it "reports real line and column numbers, not token indexes" do
      edits = parser.compute("alpha beta\ngamma delta", "alpha beta\ngamma DELTA")

      expect(edits.first[:old]).to include(line: 2, column: 7)
    end

    it "restores whitespace the tokenizer discarded, via the source offsets" do
      # Spaces are not tokens, but a multi-token edit's text must still include them.
      edits = parser.compute("a b c", "a X Y Z c")

      expect(edits.first[:new][:text]).to eq("X Y Z")
    end

    it "produces offsets that address exactly the text they report" do
      old_content = "one two three"
      new_content = "one TWO THREE"
      edits = parser.compute(old_content, new_content)

      expect(edits).to all(
        satisfy do |e|
          old_content[e[:old][:start]...e[:old][:end]] == e[:old][:text] &&
            new_content[e[:new][:start]...e[:new][:end]] == e[:new][:text]
        end
      )
    end
  end
end
