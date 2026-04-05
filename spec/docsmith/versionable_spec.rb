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

  describe "query methods" do
    let(:article) { create(:article, body: "v1 content") }

    before do
      allow(Article).to receive(:docsmith_resolved_config)
        .and_return(Article.docsmith_resolved_config.merge(auto_save: false))
      article.save_version!(author: nil)
      article.update_column(:body, "v2 content")
      article.instance_variable_set(:@_docsmith_document, nil)
      article.send(:_sync_docsmith_content!)
      article.send(:_docsmith_document).update_column(:content, "v2 content")
      article.save_version!(author: nil)
    end

    describe "#versions" do
      it "returns an AR relation of DocumentVersions ordered by version_number" do
        expect(article.versions.count).to eq(2)
        expect(article.versions.first.version_number).to eq(1)
        expect(article.versions.last.version_number).to eq(2)
      end
    end

    describe "#current_version" do
      it "returns the latest DocumentVersion" do
        expect(article.current_version.version_number).to eq(2)
      end
    end

    describe "#version(n)" do
      it "returns the DocumentVersion with that version_number" do
        expect(article.version(1).content).to eq("v1 content")
      end

      it "returns nil for unknown version number" do
        expect(article.version(99)).to be_nil
      end
    end
  end

  describe "#restore_version!" do
    let(:article) { create(:article, body: "original") }

    before do
      allow(Article).to receive(:docsmith_resolved_config)
        .and_return(Article.docsmith_resolved_config.merge(auto_save: false))
      article.save_version!(author: nil)
      article.update_columns(body: "edited")
      article.instance_variable_set(:@_docsmith_document, nil)
      article.send(:_docsmith_document).update_column(:content, "edited")
      article.save_version!(author: nil)
    end

    it "creates a new version with the old content" do
      new_ver = article.restore_version!(1, author: nil)
      expect(new_ver.content).to eq("original")
      expect(new_ver.version_number).to eq(3)
    end

    it "syncs restored content back to the model's body column" do
      article.restore_version!(1, author: nil)
      expect(article.reload.body).to eq("original")
    end

    it "raises VersionNotFound for unknown version" do
      expect { article.restore_version!(99, author: nil) }
        .to raise_error(Docsmith::VersionNotFound)
    end
  end

  describe "tag methods" do
    let(:article) { create(:article, body: "v1") }
    before do
      allow(Article).to receive(:docsmith_resolved_config)
        .and_return(Article.docsmith_resolved_config.merge(auto_save: false))
      article.save_version!(author: nil)
    end

    describe "#tag_version!" do
      it "creates a VersionTag" do
        expect { article.tag_version!(1, name: "v1.0", author: nil) }
          .to change { Docsmith::VersionTag.count }.by(1)
      end

      it "raises TagAlreadyExists on duplicate name" do
        article.tag_version!(1, name: "v1.0", author: nil)
        expect { article.tag_version!(1, name: "v1.0", author: nil) }
          .to raise_error(Docsmith::TagAlreadyExists)
      end
    end

    describe "#tagged_version" do
      it "returns the DocumentVersion for a given tag" do
        article.tag_version!(1, name: "release", author: nil)
        expect(article.tagged_version("release").version_number).to eq(1)
      end

      it "returns nil for unknown tag" do
        expect(article.tagged_version("nope")).to be_nil
      end
    end

    describe "#version_tags" do
      it "returns array of tag names for a version" do
        article.tag_version!(1, name: "v1.0", author: nil)
        article.tag_version!(1, name: "stable", author: nil)
        expect(article.version_tags(1)).to contain_exactly("v1.0", "stable")
      end

      it "returns empty array for untagged version" do
        expect(article.version_tags(1)).to eq([])
      end
    end
  end

  describe "#diff_from" do
    include FactoryBot::Syntax::Methods

    let(:article) { create(:article, body: "line one\nline two") }
    let(:user)    { create(:user) }

    before do
      allow(Article).to receive(:docsmith_resolved_config)
        .and_return(Article.docsmith_resolved_config.merge(auto_save: false))
      article.save_version!(author: user)
      # Update article and document
      doc = article.send(:_docsmith_document)
      article.update_columns(body: "line one\nline two\nline three")
      doc.update_column(:content, "line one\nline two\nline three")
      # Use VersionManager directly to avoid caching issues
      Docsmith::VersionManager.save!(doc, author: user, config: Article.docsmith_resolved_config)
    end

    it "returns a Diff::Result comparing version N to current" do
      result = article.diff_from(1)
      expect(result).to be_a(Docsmith::Diff::Result)
      expect(result.from_version).to eq(1)
      expect(result.additions).to eq(1)
    end

    it "raises ActiveRecord::RecordNotFound for a non-existent version" do
      expect { article.diff_from(99) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#diff_between" do
    include FactoryBot::Syntax::Methods

    let(:article) { create(:article, body: "v1 content") }
    let(:user)    { create(:user) }

    before do
      allow(Article).to receive(:docsmith_resolved_config)
        .and_return(Article.docsmith_resolved_config.merge(auto_save: false))
      article.save_version!(author: user)
      article.update_columns(body: "v2 content")
      article.instance_variable_set(:@_docsmith_document, nil)
      article.send(:_docsmith_document).update_column(:content, "v2 content")
      article.save_version!(author: user)
      article.update_columns(body: "v3 content")
      article.instance_variable_set(:@_docsmith_document, nil)
      article.send(:_docsmith_document).update_column(:content, "v3 content")
      article.save_version!(author: user)
    end

    it "returns a Diff::Result comparing two named versions" do
      result = article.diff_between(1, 3)
      expect(result).to be_a(Docsmith::Diff::Result)
      expect(result.from_version).to eq(1)
      expect(result.to_version).to eq(3)
    end
  end

  describe "#add_comment!" do
    include FactoryBot::Syntax::Methods

    let(:article) { create(:article, body: "hello world content here") }
    let(:user)    { create(:user) }

    before do
      allow(Article).to receive(:docsmith_resolved_config).and_return(
        { content_field: :body, content_type: :markdown, auto_save: false, debounce: 30, max_versions: nil, content_extractor: nil }
      )
      article.save_version!(author: user)
    end

    it "creates a document-level comment on the specified version" do
      comment = article.add_comment!(version: 1, body: "Great", author: user)
      expect(comment).to be_a(Docsmith::Comments::Comment)
      expect(comment.anchor_type).to eq("document")
    end

    it "creates a range-anchored inline comment when anchor is given" do
      comment = article.add_comment!(
        version: 1, body: "cite", author: user,
        anchor: { start_offset: 0, end_offset: 5 }
      )
      expect(comment.anchor_type).to eq("range")
    end
  end

  describe "#comments" do
    include FactoryBot::Syntax::Methods

    let(:article) { create(:article, body: "content") }
    let(:user)    { create(:user) }

    before do
      allow(Article).to receive(:docsmith_resolved_config).and_return(
        { content_field: :body, content_type: :markdown, auto_save: false, debounce: 30, max_versions: nil, content_extractor: nil }
      )
      article.save_version!(author: user)
      article.add_comment!(version: 1, body: "first",  author: user)
      article.add_comment!(version: 1, body: "second", author: user)
    end

    it "returns all comments across all versions as an AR relation" do
      expect(article.comments.count).to eq(2)
    end
  end

  describe "#comments_on" do
    include FactoryBot::Syntax::Methods

    let(:article) { create(:article, body: "content") }
    let(:user)    { create(:user) }

    before do
      allow(Article).to receive(:docsmith_resolved_config).and_return(
        { content_field: :body, content_type: :markdown, auto_save: false, debounce: 30, max_versions: nil, content_extractor: nil }
      )
      article.save_version!(author: user)
      article.body = "updated"
      article.save!
      article.save_version!(author: user)
      article.add_comment!(version: 1, body: "on v1", author: user)
      article.add_comment!(version: 2, body: "on v2", author: user)
    end

    it "returns only comments on the specified version" do
      expect(article.comments_on(version: 1).map(&:body)).to eq(["on v1"])
      expect(article.comments_on(version: 2).map(&:body)).to eq(["on v2"])
    end
  end

  describe "#unresolved_comments" do
    include FactoryBot::Syntax::Methods

    let(:article) { create(:article, body: "content") }
    let(:user)    { create(:user) }

    before do
      allow(Article).to receive(:docsmith_resolved_config).and_return(
        { content_field: :body, content_type: :markdown, auto_save: false, debounce: 30, max_versions: nil, content_extractor: nil }
      )
      article.save_version!(author: user)
      article.add_comment!(version: 1, body: "unresolved", author: user)
      c2 = article.add_comment!(version: 1, body: "resolved",   author: user)
      Docsmith::Comments::Manager.resolve!(c2, by: user)
    end

    it "returns only unresolved comments" do
      expect(article.unresolved_comments.count).to eq(1)
      expect(article.unresolved_comments.first.body).to eq("unresolved")
    end
  end

  describe "#migrate_comments!" do
    include FactoryBot::Syntax::Methods

    let(:article) { create(:article, body: "hello world") }
    let(:user)    { create(:user) }

    before do
      allow(Article).to receive(:docsmith_resolved_config).and_return(
        { content_field: :body, content_type: :markdown, auto_save: false, debounce: 30, max_versions: nil, content_extractor: nil }
      )
      article.save_version!(author: user)
      article.add_comment!(version: 1, body: "note", author: user)
      article.body = "hello world updated"
      article.save!
      article.save_version!(author: user)
    end

    it "copies comments from one version to another" do
      article.migrate_comments!(from: 1, to: 2)
      expect(article.comments_on(version: 2).count).to eq(1)
      expect(article.comments_on(version: 2).first.body).to eq("note")
    end
  end
end
