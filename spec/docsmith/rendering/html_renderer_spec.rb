# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Rendering::HtmlRenderer do
  subject(:renderer) { described_class.new }

  def stub_version(content:, content_type:)
    double("version", content: content, content_type: content_type)
  end

  describe "#render" do
    context "with html content_type" do
      let(:payload) { %(<p>Hi</p><script>alert(document.cookie)</script>) }

      context "with no html_sanitizer configured (the default)" do
        it "escapes the content instead of emitting it verbatim" do
          html = renderer.render(stub_version(content: payload, content_type: "html"))

          expect(html).to include("docsmith-html")
          expect(html).to include("&lt;script&gt;")
          expect(html).not_to include("<script>")
        end
      end

      context "with a callable html_sanitizer" do
        it "returns whatever the sanitizer produces" do
          Docsmith.configure { |c| c.html_sanitizer = ->(raw) { raw.gsub(%r{<script.*?</script>}m, "") } }

          html = renderer.render(stub_version(content: payload, content_type: "html"))

          expect(html).to eq("<p>Hi</p>")
        end
      end

      context "with html_sanitizer = :unsafe_raw" do
        it "passes the content through verbatim" do
          Docsmith.configure { |c| c.html_sanitizer = :unsafe_raw }

          expect(renderer.render(stub_version(content: payload, content_type: "html"))).to eq(payload)
        end
      end

      context "with a non-callable html_sanitizer" do
        it "raises rather than silently degrading to raw output" do
          Docsmith.configure { |c| c.html_sanitizer = "nope" }

          expect { renderer.render(stub_version(content: payload, content_type: "html")) }
            .to raise_error(Docsmith::InvalidHtmlSanitizer, /must respond to #call/)
        end
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
