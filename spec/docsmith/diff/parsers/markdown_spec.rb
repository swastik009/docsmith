# frozen_string_literal: true

require "spec_helper"
require "docsmith/diff/parsers/markdown"

RSpec.describe Docsmith::Diff::Parsers::Markdown do
  subject(:parser) { described_class.new }

  describe "#compute" do
    it "detects a word addition between versions" do
      # "Hello world" → "Hello Ruby world"
      # Old tokens: ["Hello", "world"]
      # New tokens: ["Hello", "Ruby", "world"]
      # LCS: ["Hello", "world"] — "Ruby" is inserted
      changes = parser.compute("Hello world", "Hello Ruby world")
      expect(changes).to include(a_hash_including(type: :addition, content: "Ruby"))
    end

    it "detects a word deletion between versions" do
      # "Hello Ruby world" → "Hello world"
      changes = parser.compute("Hello Ruby world", "Hello world")
      expect(changes).to include(a_hash_including(type: :deletion, content: "Ruby"))
    end

    it "detects a word modification" do
      # "Hello world" → "Hello Ruby"
      # Old tokens: ["Hello", "world"]
      # New tokens: ["Hello", "Ruby"]
      # LCS: ["Hello"] — "world" modified to "Ruby"
      changes = parser.compute("Hello world", "Hello Ruby")
      expect(changes).to include(a_hash_including(
        type:        :modification,
        old_content: "world",
        new_content: "Ruby"
      ))
    end

    it "returns empty array for identical content" do
      expect(parser.compute("same text", "same text")).to be_empty
    end

    it "treats each whitespace-delimited word as a separate token" do
      # Adding a new line adds 3 tokens: newline, word, word
      # "line one\nline two" → "line one\nline two\nline three"
      # Old tokens: ["line", "one", "\n", "line", "two"]
      # New tokens: ["line", "one", "\n", "line", "two", "\n", "line", "three"]
      # Additions: 3 tokens ("\n", "line", "three")
      changes = parser.compute("line one\nline two", "line one\nline two\nline three")
      additions = changes.select { |c| c[:type] == :addition }
      expect(additions.count).to eq(3)
      expect(additions.map { |c| c[:content] }).to contain_exactly("\n", "line", "three")
    end

    it "preserves newlines as distinct tokens for paragraph detection" do
      # A blank-line paragraph break is one "\n\n" token
      changes = parser.compute("Para one", "Para one\n\nPara two")
      expect(changes).to include(a_hash_including(type: :addition, content: "\n\n"))
    end

    it "returns change hashes with :line (token index), :type, and :content keys" do
      changes = parser.compute("foo", "foo bar")
      addition = changes.find { |c| c[:type] == :addition }
      expect(addition).to include(:line, :type, :content)
    end
  end
end
