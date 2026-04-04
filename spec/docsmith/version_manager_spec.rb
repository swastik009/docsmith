# frozen_string_literal: true

RSpec.describe Docsmith::VersionManager do
  let(:doc)    { create(:docsmith_document, content: "initial") }
  let(:user)   { create(:user) }
  let(:config) { Docsmith::Configuration.resolve({}, Docsmith.configuration) }

  describe ".save!" do
    it "creates a DocumentVersion with version_number 1 for first save" do
      version = described_class.save!(doc, author: user, config: config)
      expect(version).to be_a(Docsmith::DocumentVersion)
      expect(version.version_number).to eq(1)
      expect(version.content).to eq("initial")
    end

    it "increments version_number on subsequent saves" do
      described_class.save!(doc, author: user, config: config)
      doc.update_column(:content, "version two")
      v2 = described_class.save!(doc, author: user, config: config)
      expect(v2.version_number).to eq(2)
    end

    it "returns nil when content is identical to latest version" do
      described_class.save!(doc, author: user, config: config)
      result = described_class.save!(doc, author: user, config: config)
      expect(result).to be_nil
    end

    it "increments versions_count on document" do
      expect { described_class.save!(doc, author: user, config: config) }
        .to change { doc.reload.versions_count }.from(0).to(1)
    end

    it "sets last_versioned_at on document" do
      expect { described_class.save!(doc, author: user, config: config) }
        .to change { doc.reload.last_versioned_at }.from(nil)
    end

    it "stores the author polymorphically" do
      version = described_class.save!(doc, author: user, config: config)
      expect(version.author).to eq(user)
    end

    it "stores the change_summary" do
      version = described_class.save!(doc, author: user, summary: "Initial draft", config: config)
      expect(version.change_summary).to eq("Initial draft")
    end

    it "fires version_created event with record and document" do
      received = nil
      Docsmith.configure { |c| c.on(:version_created) { |e| received = e } }
      described_class.save!(doc, author: user, config: config)
      expect(received).to be_a(Docsmith::Events::Event)
      expect(received.document).to eq(doc)
      expect(received.author).to eq(user)
    end

    context "when max_versions is set" do
      let(:config) { Docsmith::Configuration.resolve({ max_versions: 2 }, Docsmith.configuration) }

      it "prunes the oldest untagged version when limit exceeded" do
        described_class.save!(doc, author: user, config: config)
        doc.update_column(:content, "v2")
        described_class.save!(doc, author: user, config: config)
        doc.update_column(:content, "v3")
        described_class.save!(doc, author: user, config: config)

        expect(doc.reload.document_versions.pluck(:version_number)).not_to include(1)
      end

      it "raises MaxVersionsExceeded when all versions are tagged" do
        v1 = described_class.save!(doc, author: user, config: config)
        Docsmith::VersionTag.create!(document: doc, version: v1, name: "t1",
                                     created_at: Time.current)
        doc.update_column(:content, "v2")
        v2 = described_class.save!(doc, author: user, config: config)
        Docsmith::VersionTag.create!(document: doc, version: v2, name: "t2",
                                     created_at: Time.current)
        doc.update_column(:content, "v3")

        expect { described_class.save!(doc, author: user, config: config) }
          .to raise_error(Docsmith::MaxVersionsExceeded)
      end
    end
  end
end
