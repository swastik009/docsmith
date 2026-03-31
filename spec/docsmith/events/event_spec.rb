# frozen_string_literal: true

RSpec.describe Docsmith::Events::Event do
  it "is a Struct with keyword_init" do
    event = described_class.new(record: "r", document: "d", version: "v", author: "a")
    expect(event.record).to eq("r")
    expect(event.document).to eq("d")
    expect(event.version).to eq("v")
    expect(event.author).to eq("a")
  end

  it "accepts optional fields" do
    event = described_class.new(
      record: "r", document: "d", version: "v", author: "a",
      from_version: "fv", tag_name: "t1"
    )
    expect(event.from_version).to eq("fv")
    expect(event.tag_name).to eq("t1")
  end

  it "defaults optional fields to nil" do
    event = described_class.new(record: "r", document: "d", version: "v", author: "a")
    expect(event.from_version).to be_nil
    expect(event.tag_name).to be_nil
  end
end
