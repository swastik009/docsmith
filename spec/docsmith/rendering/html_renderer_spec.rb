# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Rendering::HtmlRenderer do
  subject(:renderer) { described_class.new }

  def stub_version(content:, content_type:)
    double("version", content: content, content_type: content_type)
  end

  describe "#render" do
    context "with html content_type" do
      it "returns the content as-is" do
        expect(renderer.render(stub_version(content: "<p>Hello</p>", content_type: "html"))).to eq("<p>Hello</p>")
      end
    end

    context "with markdown content_type" do
      it "wraps content in a pre tag with docsmith-markdown class" do
        html = renderer.render(stub_version(content: "# Hello\nWorld", content_type: "markdown"))
        expect(html).to include("docsmith-markdown")
        expect(html).to include("# Hello")
      end
    end

    context "with json content_type" do
      it "pretty-prints JSON in a pre tag with docsmith-json class" do
        html = renderer.render(stub_version(content: '{"key":"value"}', content_type: "json"))
        expect(html).to include("docsmith-json")
        expect(html).to include("&quot;key&quot;")
      end
    end

    context "with invalid JSON and json content_type" do
      it "falls back gracefully without raising" do
        expect { renderer.render(stub_version(content: "not-json", content_type: "json")) }.not_to raise_error
      end
    end
  end
end
