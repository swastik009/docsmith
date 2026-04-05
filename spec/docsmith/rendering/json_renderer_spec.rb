# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Rendering::JsonRenderer do
  subject(:renderer) { described_class.new }

  def stub_version(content:, content_type:)
    double("version", content: content, content_type: content_type)
  end

  describe "#render" do
    context "with json content_type" do
      it "returns pretty-printed JSON" do
        result = renderer.render(stub_version(content: '{"key":"value"}', content_type: "json"))
        parsed = JSON.parse(result)
        expect(parsed["key"]).to eq("value")
      end
    end

    context "with non-json content_type" do
      it "wraps content in a JSON envelope with content_type and content keys" do
        result = renderer.render(stub_version(content: "# Markdown", content_type: "markdown"))
        parsed = JSON.parse(result)
        expect(parsed["content_type"]).to eq("markdown")
        expect(parsed["content"]).to eq("# Markdown")
      end
    end

    context "with invalid JSON content and json content_type" do
      it "returns an error envelope without raising" do
        result = renderer.render(stub_version(content: "broken", content_type: "json"))
        parsed = JSON.parse(result)
        expect(parsed["error"]).to eq("invalid_json")
      end
    end
  end
end
