# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Diff::Renderers::Base do
  subject(:renderer) { described_class.new }

  describe "#compute" do
    it "detects added lines" do
      changes = renderer.compute("line one\nline two", "line one\nline two\nline three")
      expect(changes).to include(a_hash_including(type: :addition, content: "line three"))
    end

    it "detects deleted lines" do
      changes = renderer.compute("line one\nline two", "line one")
      expect(changes).to include(a_hash_including(type: :deletion, content: "line two"))
    end

    it "detects modified lines" do
      changes = renderer.compute("hello world", "hello ruby")
      expect(changes).to include(a_hash_including(type: :modification, old_content: "hello world", new_content: "hello ruby"))
    end

    it "returns empty array for identical content" do
      expect(renderer.compute("same", "same")).to be_empty
    end

    it "includes 1-indexed line numbers" do
      changes = renderer.compute("a\nb", "a\nc")
      mod = changes.find { |c| c[:type] == :modification }
      expect(mod[:line]).to eq(2)
    end
  end

  describe "#render_html" do
    it "wraps additions in <ins> tags with docsmith-addition class" do
      changes = [{ type: :addition, line: 1, content: "new line" }]
      expect(renderer.render_html(changes)).to include('<ins class="docsmith-addition">new line</ins>')
    end

    it "wraps deletions in <del> tags with docsmith-deletion class" do
      changes = [{ type: :deletion, line: 1, content: "old line" }]
      expect(renderer.render_html(changes)).to include('<del class="docsmith-deletion">old line</del>')
    end

    it "escapes HTML special characters in content" do
      changes = [{ type: :addition, line: 1, content: "<script>alert('xss')</script>" }]
      html = renderer.render_html(changes)
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
