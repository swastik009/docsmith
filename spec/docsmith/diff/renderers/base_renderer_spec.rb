# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Diff::Renderers::Base do
  subject(:renderer) { described_class.new }

  # Helper: an edit's offsets must actually address the text it claims.
  def offsets_agree_with_text?(edits, old_content, new_content)
    edits.all? do |e|
      old_content[e[:old][:start]...e[:old][:end]] == e[:old][:text] &&
        new_content[e[:new][:start]...e[:new][:end]] == e[:new][:text]
    end
  end

  describe "#compute" do
    it "reports an inserted line as an insert with a zero-width old span" do
      edits = renderer.compute("line one\nline two", "line one\nline two\nline three")

      expect(edits.length).to eq(1)
      expect(edits.first[:type]).to eq(:insert)
      expect(edits.first[:new][:text]).to eq("line three")
      expect(edits.first[:old][:start]).to eq(edits.first[:old][:end])
    end

    it "reports a deleted line as a delete with a zero-width new span" do
      edits = renderer.compute("line one\nline two", "line one")

      expect(edits.first[:type]).to eq(:delete)
      expect(edits.first[:old][:text]).to eq("line two")
      expect(edits.first[:new][:start]).to eq(edits.first[:new][:end])
    end

    it "reports a changed line as a replace carrying both sides" do
      edits = renderer.compute("hello world", "hello ruby")

      expect(edits.first).to include(type: :replace)
      expect(edits.first[:old][:text]).to eq("hello world")
      expect(edits.first[:new][:text]).to eq("hello ruby")
    end

    it "returns empty array for identical content" do
      expect(renderer.compute("same", "same")).to be_empty
    end

    # The defect this redesign exists to fix: `line` used to be a token index
    # dressed up as a line number, and it mixed old-side and new-side coordinates.
    it "reports genuine 1-indexed line and column numbers" do
      edits = renderer.compute("line one\nline two\nline three",
                               "line one\nline TWO\nline three")

      expect(edits.first[:old]).to include(line: 2, column: 1)
      expect(edits.first[:new]).to include(line: 2, column: 1)
    end

    it "never reports a line number beyond the document's real line count" do
      old_content = "a\nb"
      new_content = "x y z w v\nb"
      edits = renderer.compute(old_content, new_content)

      expect(edits.map { |e| e[:new][:line] }.max).to be <= new_content.lines.size
    end

    it "produces offsets that address exactly the text they report" do
      old_content = "one\ntwo\nthree"
      new_content = "one\nTWO CHANGED\nthree"

      expect(offsets_agree_with_text?(renderer.compute(old_content, new_content),
                                      old_content, new_content)).to be(true)
    end

    it "collapses a contiguous run into a single edit" do
      # Four consecutive new lines are one insertion, not four entries.
      edits = renderer.compute("a\nz", "a\nb\nc\nd\nz")

      expect(edits.length).to eq(1)
      expect(edits.first[:type]).to eq(:insert)
    end

    it "keeps non-adjacent edits separate" do
      edits = renderer.compute("a\nkeep\nb", "X\nkeep\nY")

      expect(edits.length).to eq(2)
    end
  end

  describe "#render_html" do
    def span(text) = { start: 0, end: text.length, line: 1, column: 1, text: text }

    it "wraps insertions in <ins> tags with docsmith-addition class" do
      edits = [{ type: :insert, old: span(""), new: span("new line") }]
      expect(renderer.render_html(edits)).to include('<ins class="docsmith-addition">new line</ins>')
    end

    it "wraps deletions in <del> tags with docsmith-deletion class" do
      edits = [{ type: :delete, old: span("old line"), new: span("") }]
      expect(renderer.render_html(edits)).to include('<del class="docsmith-deletion">old line</del>')
    end

    it "renders a replace as a deletion followed by an insertion" do
      edits = [{ type: :replace, old: span("before"), new: span("after") }]
      html  = renderer.render_html(edits)

      expect(html).to include('<del class="docsmith-deletion">before</del>')
      expect(html).to include('<ins class="docsmith-addition">after</ins>')
    end

    it "escapes HTML special characters in content" do
      edits = [{ type: :insert, old: span(""), new: span("<script>alert('xss')</script>") }]
      html  = renderer.render_html(edits)

      expect(html).not_to include("<script>")
      expect(html).to include("&lt;script&gt;")
    end

    it "wraps output in a docsmith-diff div" do
      expect(renderer.render_html([])).to start_with('<div class="docsmith-diff">')
    end
  end
end

RSpec.describe Docsmith::Diff::Renderers::Registry do
  after { described_class.reset! }

  describe ".for" do
    it "returns Base for unregistered content types" do
      expect(described_class.for("markdown")).to eq(Docsmith::Diff::Renderers::Base)
    end

    it "returns the registered renderer for a registered type" do
      custom = Class.new(Docsmith::Diff::Renderers::Base)
      described_class.register("html", custom)
      expect(described_class.for("html")).to eq(custom)
    end

    it "accepts symbol content types" do
      custom = Class.new(Docsmith::Diff::Renderers::Base)
      described_class.register(:json, custom)
      expect(described_class.for("json")).to eq(custom)
    end
  end

  describe ".register" do
    it "adds a renderer to the registry" do
      custom = Class.new(Docsmith::Diff::Renderers::Base)
      described_class.register("custom", custom)
      expect(described_class.all).to include("custom" => custom)
    end
  end
end
