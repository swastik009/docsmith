# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Rendering::JsonRenderer do
  subject(:renderer) { described_class.new }

  # Real records, not doubles. The previous spec stubbed a double exposing only
  # content and content_type, which is why USAGE.md could promise a "version" key
  # the renderer never emitted.
  let(:author)  { create(:user) }
  let(:document) { create(:document, content_type: "markdown") }

  let(:version) do
    create(:document_version,
           document:       document,
           version_number: 2,
           content:        "# Hello\n\nSecond draft.",
           content_type:   "markdown",
           change_summary: "Second draft",
           author:         author,
           created_at:     Time.utc(2026, 3, 1, 14, 22, 0))
  end

  describe "#to_h" do
    it "returns the full documented envelope" do
      expect(renderer.to_h(version)).to eq(
        "schema_version" => 1,
        "document_id"    => document.id,
        "version_number" => 2,
        "content_type"   => "markdown",
        "content"        => "# Hello\n\nSecond draft.",
        "change_summary" => "Second draft",
        "author"         => { "type" => "User", "id" => author.id },
        "metadata"       => {},
        "created_at"     => "2026-03-01T14:22:00.000Z"
      )
    end

    it "emits author as nil when there is no author" do
      version.update!(author: nil)
      expect(renderer.to_h(version)["author"]).to be_nil
    end

    it "uses one shape for every content_type" do
      shapes = %w[markdown html json].each_with_index.map do |type, i|
        content = type == "json" ? '{"a":1}' : "body"
        v = create(:document_version, document: document, version_number: 20 + i,
                                     content: content, content_type: type)
        renderer.to_h(v).keys
      end

      expect(shapes.uniq.length).to eq(1)
    end
  end

  describe "content fidelity" do
    it "returns the exact stored bytes for a json document, unreformatted" do
      minified = '{"b":2,"a":[1,{"c":null}]}'
      v = create(:document_version, document: document, version_number: 3,
                                    content: minified, content_type: "json")

      expect(renderer.to_h(v)["content"]).to eq(minified)
    end

    it "round-trips markdown content byte for byte" do
      raw = "line1\n\n  indented\ttab\ntrailing   \n"
      v = create(:document_version, document: document, version_number: 4,
                                    content: raw, content_type: "markdown")

      expect(JSON.parse(renderer.render(v))["content"]).to eq(raw)
    end
  end

  describe "include_parsed" do
    let(:json_version) do
      create(:document_version, document: document, version_number: 5,
                                content: '{"title":"Doc","tags":["a"]}', content_type: "json")
    end

    it "adds the parsed document under data" do
      expect(renderer.to_h(json_version, include_parsed: true)["data"])
        .to eq("title" => "Doc", "tags" => ["a"])
    end

    it "still returns the exact stored string in content" do
      out = renderer.to_h(json_version, include_parsed: true)
      expect(out["content"]).to eq('{"title":"Doc","tags":["a"]}')
    end

    it "omits data unless asked" do
      expect(renderer.to_h(json_version)).not_to have_key("data")
    end

    it "is a no-op for non-json content types" do
      expect(renderer.to_h(version, include_parsed: true)).not_to have_key("data")
    end

    it "raises InvalidJsonContent when the content does not parse" do
      broken = create(:document_version, document: document, version_number: 6,
                                         content: "{not json", content_type: "json")

      expect { renderer.to_h(broken, include_parsed: true) }
        .to raise_error(Docsmith::InvalidJsonContent, /does not parse/)
    end

    it "never parses on the default path, so malformed content cannot fail it" do
      broken = create(:document_version, document: document, version_number: 7,
                                         content: "{not json", content_type: "json")

      expect { renderer.render(broken) }.not_to raise_error
      expect(JSON.parse(renderer.render(broken))["content"]).to eq("{not json")
    end
  end

  describe "#render" do
    it "is to_h encoded as JSON" do
      expect(JSON.parse(renderer.render(version))).to eq(renderer.to_h(version))
    end
  end
end
