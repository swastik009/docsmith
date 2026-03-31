# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Diff::Result do
  let(:changes) do
    [
      { type: :addition,     line: 3, content: "new line" },
      { type: :deletion,     line: 1, content: "old line" },
      { type: :modification, line: 2, old_content: "before", new_content: "after" }
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

  describe "#additions" do
    it "counts addition-type changes only" do
      expect(result.additions).to eq(1)
    end
  end

  describe "#deletions" do
    it "counts deletion-type changes only" do
      expect(result.deletions).to eq(1)
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

    it "includes stats block with additions and deletions" do
      parsed = JSON.parse(result.to_json)
      expect(parsed["stats"]).to eq("additions" => 1, "deletions" => 1)
    end

    it "includes content_type, from_version, to_version" do
      parsed = JSON.parse(result.to_json)
      expect(parsed["content_type"]).to eq("markdown")
      expect(parsed["from_version"]).to eq(1)
      expect(parsed["to_version"]).to eq(3)
    end

    it "serializes addition changes with position and content" do
      parsed = JSON.parse(result.to_json)
      addition = parsed["changes"].find { |c| c["type"] == "addition" }
      expect(addition).to include("position" => { "line" => 3 }, "content" => "new line")
    end

    it "serializes modification changes with old_content and new_content" do
      parsed = JSON.parse(result.to_json)
      mod = parsed["changes"].find { |c| c["type"] == "modification" }
      expect(mod).to include("old_content" => "before", "new_content" => "after")
    end
  end
end
