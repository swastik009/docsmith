# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Diff::Result do
  def span(start, text, line: 1, column: 1)
    { start: start, end: start + text.length, line: line, column: column, text: text }
  end

  let(:changes) do
    [
      { type: :insert,  old: span(10, ""),       new: span(10, "new line") },
      { type: :delete,  old: span(0, "old line"), new: span(0, "") },
      { type: :replace, old: span(30, "before"),  new: span(30, "after") }
    ]
  end

  subject(:result) do
    described_class.new(
      content_type: "markdown",
      from_version: 1,
      to_version:   3,
      changes:      changes
    )
  end

  it "exposes content_type, from_version, to_version, changes" do
    expect(result.content_type).to eq("markdown")
    expect(result.from_version).to eq(1)
    expect(result.to_version).to eq(3)
    expect(result.changes).to eq(changes)
  end

  describe "counts" do
    it "counts each edit kind separately" do
      expect([result.insertions, result.deletions, result.replacements]).to eq([1, 1, 1])
    end
  end

  describe "#to_html" do
    it "returns HTML string with diff markup" do
      html = result.to_html
      expect(html).to include("docsmith-diff")
      expect(html).to include("docsmith-addition")
      expect(html).to include("docsmith-deletion")
    end
  end

  describe "#to_json" do
    it "returns valid JSON" do
      expect { JSON.parse(result.to_json) }.not_to raise_error
    end

    it "includes a stats block counting modifications separately" do
      parsed = JSON.parse(result.to_json)
      expect(parsed["stats"]).to eq(
        "insertions" => 1, "deletions" => 1, "replacements" => 1, "total" => 3
      )
    end

    it "includes content_type, from_version, to_version" do
      parsed = JSON.parse(result.to_json)
      expect(parsed["content_type"]).to eq("markdown")
      expect(parsed["from_version"]).to eq(1)
      expect(parsed["to_version"]).to eq(3)
    end

    it "serializes every edit with the same keys and both sides" do
      parsed = JSON.parse(result.to_json)

      expect(parsed["changes"].map(&:keys).uniq).to eq([%w[type old new]])
      expect(parsed["changes"].flat_map { |c| [c["old"].keys, c["new"].keys] }.uniq)
        .to eq([%w[start end line column text]])
    end

    it "serializes an insert with a zero-width old span" do
      insert = JSON.parse(result.to_json)["changes"].find { |c| c["type"] == "insert" }

      expect(insert["new"]).to include("text" => "new line")
      expect(insert["old"]["start"]).to eq(insert["old"]["end"])
      expect(insert["old"]["text"]).to eq("")
    end

    it "serializes a replace carrying both old and new text" do
      replace = JSON.parse(result.to_json)["changes"].find { |c| c["type"] == "replace" }

      expect(replace["old"]).to include("text" => "before")
      expect(replace["new"]).to include("text" => "after")
    end
  end

  describe "#as_json" do
    it "matches the parsed output of #to_json exactly" do
      expect(result.as_json).to eq(JSON.parse(result.to_json))
    end

    it "includes schema_version" do
      expect(result.as_json["schema_version"]).to eq(Docsmith::JSON_SCHEMA_VERSION)
    end
  end

  # The regression that made third-party clients receive a different schema than
  # the documented one. Without as_json, nesting fell through to Object#as_json
  # (instance_values): no "stats", and "line" instead of "position".
  describe "nesting (the ActiveSupport trap)" do
    it "produces the same payload nested in a Hash as standalone" do
      expect(JSON.parse({ diff: result }.to_json)).to eq("diff" => JSON.parse(result.to_json))
    end

    it "produces the same payload nested in an Array as standalone" do
      expect(JSON.parse([result].to_json)).to eq([JSON.parse(result.to_json)])
    end

    it "keeps stats when nested" do
      nested = JSON.parse({ diff: result }.to_json)["diff"]
      expect(nested["stats"]).to eq(
        "insertions" => 1, "deletions" => 1, "replacements" => 1, "total" => 3
      )
    end

    it "keeps both coordinate sides when nested" do
      nested = JSON.parse({ diff: result }.to_json)["diff"]

      expect(nested["changes"].map { |c| c["old"] }).to all(be_a(Hash))
      expect(nested["changes"].map { |c| c["new"] }).to all(be_a(Hash))
    end

    it "round-trips through JSON.generate" do
      expect(JSON.parse(JSON.generate(result))).to eq(JSON.parse(result.to_json))
    end
  end

  describe "#stats" do
    it "reports a replace-only diff as non-zero" do
      only_replaced = described_class.new(
        content_type: "markdown", from_version: 1, to_version: 2,
        changes: [{ type: :replace, old: span(0, "a"), new: span(0, "b") }]
      )

      expect(only_replaced.stats).to eq(
        "insertions" => 0, "deletions" => 0, "replacements" => 1, "total" => 1
      )
    end

    it "keeps insertions and deletions as pure counts" do
      expect([result.insertions, result.deletions, result.replacements]).to eq([1, 1, 1])
    end
  end
end
