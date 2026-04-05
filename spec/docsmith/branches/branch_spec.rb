# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docsmith::Branches::Branch do
  include FactoryBot::Syntax::Methods

  let(:user)    { create(:user) }
  let(:doc)     { create(:document, content: "initial content", content_type: "markdown") }
  let(:version) { create(:document_version, document: doc, content: "initial content", version_number: 1, content_type: "markdown") }

  describe "associations" do
    it "belongs to a document" do
      branch = described_class.create!(document: doc, name: "feature", source_version: version, author: user, status: "active")
      expect(branch.document).to eq(doc)
    end

    it "belongs to source_version" do
      branch = described_class.create!(document: doc, name: "feature", source_version: version, author: user, status: "active")
      expect(branch.source_version).to eq(version)
    end
  end

  describe "validations" do
    it "enforces unique name per document at DB level" do
      described_class.create!(document: doc, name: "feature", source_version: version, author: user, status: "active")
      duplicate = described_class.new(document: doc, name: "feature", source_version: version, author: user, status: "active")
      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "validates status inclusion" do
      branch = described_class.new(document: doc, name: "b", source_version: version, author: user, status: "invalid")
      expect(branch).not_to be_valid
    end
  end

  describe "scopes" do
    before do
      described_class.create!(document: doc, name: "active-one",  source_version: version, author: user, status: "active")
      described_class.create!(document: doc, name: "merged-one",  source_version: version, author: user, status: "merged")
      described_class.create!(document: doc, name: "abandoned",   source_version: version, author: user, status: "abandoned")
    end

    it ".active returns only active branches" do
      expect(described_class.active.count).to eq(1)
    end

    it ".merged returns only merged branches" do
      expect(described_class.merged.count).to eq(1)
    end
  end
end
