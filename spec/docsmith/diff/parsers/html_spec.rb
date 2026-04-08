# frozen_string_literal: true

require "spec_helper"
require "docsmith/diff/parsers/html"

RSpec.describe Docsmith::Diff::Parsers::Html do
  subject(:parser) { described_class.new }

  describe "#compute" do
    it "treats an opening tag as one atomic token" do
      # "<p>Hello</p>" → "<span>Hello</span>"
      # Tokens: ["<p>", "Hello", "</p>"] vs ["<span>", "Hello", "</span>"]
      # Modifications: "<p>"→"<span>", "</p>"→"</span>"
      changes = parser.compute("<p>Hello</p>", "<span>Hello</span>")
      mods = changes.select { |c| c[:type] == :modification }
      expect(mods).to include(a_hash_including(old_content: "<p>", new_content: "<span>"))
      expect(mods).to include(a_hash_including(old_content: "</p>", new_content: "</span>"))
    end

    it "detects a new paragraph added (3 new tokens)" do
      # "<p>Hello</p>" → "<p>Hello</p><p>World</p>"
      # Old tokens: ["<p>", "Hello", "</p>"]
      # New tokens: ["<p>", "Hello", "</p>", "<p>", "World", "</p>"]
      # LCS: first 3 match — 3 additions: "<p>", "World", "</p>"
      changes = parser.compute("<p>Hello</p>", "<p>Hello</p><p>World</p>")
      additions = changes.select { |c| c[:type] == :addition }
      expect(additions.map { |c| c[:content] }).to contain_exactly("<p>", "World", "</p>")
    end

    it "detects a word change inside a tag" do
      changes = parser.compute("<p>Hello world</p>", "<p>Hello Ruby</p>")
      expect(changes).to include(a_hash_including(
        type:        :modification,
        old_content: "world",
        new_content: "Ruby"
      ))
    end

    it "treats tag with attributes as one atomic token" do
      # "<div class=\"foo\">" must be ONE token, not split on spaces inside the tag
      changes = parser.compute('<div class="foo">bar</div>', '<div class="baz">bar</div>')
      mods = changes.select { |c| c[:type] == :modification }
      expect(mods).to include(a_hash_including(
        old_content: '<div class="foo">',
        new_content: '<div class="baz">'
      ))
    end

    it "returns empty array for identical HTML" do
      html = "<p>Same content</p>"
      expect(parser.compute(html, html)).to be_empty
    end

    it "does not split tag delimiters < and > as separate tokens" do
      # If the tokenizer split on < and >, the open bracket "<" would be its own token.
      # Verify that no change content is exactly "<" or ">"
      changes = parser.compute("<p>a</p>", "<p>b</p>")
      all_content = changes.flat_map { |c| [c[:content], c[:old_content], c[:new_content]] }.compact
      expect(all_content).not_to include("<", ">")
    end

    it "returns change hashes with :line (token index), :type, and content keys" do
      changes = parser.compute("<p>foo</p>", "<p>foo</p><p>bar</p>")
      addition = changes.find { |c| c[:type] == :addition }
      expect(addition).to include(:line, :type, :content)
    end
  end
end
