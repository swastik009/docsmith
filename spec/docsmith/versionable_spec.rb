# frozen_string_literal: true

RSpec.describe Docsmith::Versionable do
  describe "docsmith_config DSL" do
    it "returns a ClassConfig when called without a block" do
      expect(Article.docsmith_config).to be_a(Docsmith::ClassConfig)
    end

    it "stores content_field and content_type set in the block" do
      expect(Article.docsmith_config.settings[:content_field]).to eq(:body)
      expect(Article.docsmith_config.settings[:content_type]).to eq(:markdown)
    end

    it "resolved config uses per-class settings over defaults" do
      config = Article.docsmith_resolved_config
      expect(config[:content_field]).to eq(:body)
      expect(config[:content_type]).to eq(:markdown)
    end

    it "resolved config falls through to defaults for unset keys" do
      config = Article.docsmith_resolved_config
      expect(config[:debounce]).to eq(30)
    end
  end

  describe "shadow document (_docsmith_document)" do
    let(:article) { create(:article) }

    it "creates a Docsmith::Document on first access" do
      expect { article.send(:_docsmith_document) }
        .to change { Docsmith::Document.count }.by(1)
    end

    it "is idempotent — same document returned on second call" do
      doc1 = article.send(:_docsmith_document)
      doc2 = article.send(:_docsmith_document)
      expect(doc1.id).to eq(doc2.id)
    end

    it "sets subject to the article" do
      doc = article.send(:_docsmith_document)
      expect(doc.subject).to eq(article)
    end

    it "sets content_type from the class config" do
      doc = article.send(:_docsmith_document)
      expect(doc.content_type).to eq("markdown")
    end
  end

  describe "#save_version!" do
    before(:each) do
      allow(Article).to receive(:docsmith_resolved_config)
        .and_return(Article.docsmith_resolved_config.merge(auto_save: false))
    end

    let(:article) { create(:article, body: "# Hello") }

    it "creates a DocumentVersion" do
      expect { article.save_version!(author: nil) }
        .to change { Docsmith::DocumentVersion.count }.by(1)
    end

    it "returns the new DocumentVersion" do
      version = article.save_version!(author: nil)
      expect(version).to be_a(Docsmith::DocumentVersion)
    end

    it "snapshots the content_field value" do
      version = article.save_version!(author: nil)
      expect(version.content).to eq("# Hello")
    end

    it "returns nil when content has not changed since last version" do
      article.save_version!(author: nil)
      expect(article.save_version!(author: nil)).to be_nil
    end

    it "raises InvalidContentField when content_field returns non-String" do
      allow(article).to receive(:body).and_return(42)
      expect { article.save_version!(author: nil) }
        .to raise_error(Docsmith::InvalidContentField, /content_field :body/)
    end

    it "uses content_extractor when configured" do
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "articles"
        include Docsmith::Versionable
        docsmith_config do
          content_field     :body
          content_type      :html
          content_extractor ->(r) { "extracted: #{r.body}" }
          auto_save          false
        end
      end
      article2 = klass.create!(body: "raw")
      version = article2.save_version!(author: nil)
      expect(version.content).to eq("extracted: raw")
    end
  end

  describe "#auto_save_version!" do
    let(:article) { create(:article, body: "# Auto") }

    it "creates a version outside debounce window" do
      expect { article.auto_save_version!(author: nil) }
        .to change { Docsmith::DocumentVersion.count }.by(1)
    end

    it "returns nil within debounce window" do
      article.auto_save_version!(author: nil)
      result = article.auto_save_version!(author: nil)
      expect(result).to be_nil
    end

    it "returns nil when content is unchanged" do
      article.auto_save_version!(author: nil)
      doc = article.send(:_docsmith_document)
      doc.update_column(:last_versioned_at, 60.seconds.ago)
      result = article.auto_save_version!(author: nil)
      expect(result).to be_nil
    end

    it "returns nil when auto_save is false in config" do
      allow(Article).to receive(:docsmith_resolved_config)
        .and_return(Article.docsmith_resolved_config.merge(auto_save: false))
      expect(article.auto_save_version!(author: nil)).to be_nil
    end
  end

  describe "after_save callback" do
    it "calls auto_save_version! after every AR save" do
      article = build(:article, body: "callback test")
      expect(article).to receive(:auto_save_version!)
      article.save!
    end

    it "swallows InvalidContentField during auto-save callback" do
      article = create(:article, body: "ok")
      allow(article).to receive(:body).and_return(Object.new)
      expect { article.save! }.not_to raise_error
    end
  end
end
