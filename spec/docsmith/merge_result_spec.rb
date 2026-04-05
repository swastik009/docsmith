# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::MergeResult do
  describe "successful merge" do
    let(:version) { double("version") }
    subject(:result) { described_class.new(merged_version: version, conflicts: []) }

    it "is successful" do
      expect(result.success?).to be(true)
    end

    it "has no conflicts" do
      expect(result.conflicts).to be_empty
    end

    it "exposes the merged version" do
      expect(result.merged_version).to eq(version)
    end
  end

  describe "conflicted merge" do
    subject(:result) do
      described_class.new(
        merged_version: nil,
        conflicts: [{ line: 3, branch_content: "branch text", main_content: "main text" }]
      )
    end

    it "is not successful" do
      expect(result.success?).to be(false)
    end

    it "exposes the conflict descriptions" do
      expect(result.conflicts.first[:line]).to eq(3)
    end

    it "has no merged_version" do
      expect(result.merged_version).to be_nil
    end
  end
end
