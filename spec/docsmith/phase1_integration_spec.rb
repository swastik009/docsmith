# frozen_string_literal: true

RSpec.describe "Phase 1 integration — core versioning" do
  let(:user)    { create(:user) }
  let(:article) { create(:article, body: "# Introduction\n\nFirst draft.") }

  it "full versioning lifecycle" do
    # Disable auto_save for this test so all version creation is explicit and deterministic.
    allow(Article).to receive(:docsmith_resolved_config)
      .and_return(Article.docsmith_resolved_config.merge(auto_save: false))

    # 1. First save_version! creates v1
    v1 = article.save_version!(author: user, summary: "Initial draft")
    expect(v1.version_number).to eq(1)
    expect(v1.content).to eq("# Introduction\n\nFirst draft.")
    expect(v1.author).to eq(user)
    expect(article.versions.count).to eq(1)

    # 2. Identical content returns nil
    expect(article.save_version!(author: user)).to be_nil

    # 3. Second version after content change
    article.update_columns(body: "# Introduction\n\nSecond draft.")
    article.instance_variable_set(:@_docsmith_document, nil)
    article.send(:_docsmith_document).update_column(:content, "# Introduction\n\nSecond draft.")
    v2 = article.save_version!(author: user, summary: "Second draft")
    expect(v2.version_number).to eq(2)
    expect(article.versions.count).to eq(2)

    # 4. current_version returns v2
    expect(article.current_version.version_number).to eq(2)

    # 5. version(1) returns v1
    expect(article.version(1).content).to eq("# Introduction\n\nFirst draft.")

    # 6. Restore creates v3 with v1 content
    v3 = article.restore_version!(1, author: user)
    expect(v3.version_number).to eq(3)
    expect(v3.content).to eq("# Introduction\n\nFirst draft.")
    expect(article.reload.body).to eq("# Introduction\n\nFirst draft.")

    # 7. Tagging
    article.tag_version!(1, name: "v1.0-release", author: user)
    expect(article.tagged_version("v1.0-release").version_number).to eq(1)
    expect(article.version_tags(1)).to include("v1.0-release")

    # 8. Duplicate tag raises
    expect { article.tag_version!(1, name: "v1.0-release", author: user) }
      .to raise_error(Docsmith::TagAlreadyExists)

    # 9. Events fire
    fired = []
    Docsmith.configure { |c| c.on(:version_created) { |e| fired << e.version.version_number } }
    article.update_columns(body: "v4 content")
    article.send(:_docsmith_document).update_column(:content, "v4 content")
    article.save_version!(author: user)
    expect(fired).to include(4)
  end

  it "auto_save_version! respects debounce" do
    # create(:article) already triggered auto_save → v1 exists and debounce window is active.
    # Calling auto_save_version! again immediately returns nil (within debounce).
    result = article.auto_save_version!(author: user)
    expect(result).to be_nil
    expect(article.versions.count).to eq(1)

    # A second call is also within debounce — still no new version
    result2 = article.auto_save_version!(author: user)
    expect(result2).to be_nil
    expect(article.versions.count).to eq(1)
  end

  it "standalone Docsmith::Document API" do
    doc = Docsmith::Document.create!(
      title: "Spec", content: "# Hello", content_type: "markdown"
    )
    v1 = Docsmith::VersionManager.save!(doc, author: user, summary: "Initial")
    expect(v1.version_number).to eq(1)

    doc.update_column(:content, "# Hello updated")
    v2 = Docsmith::VersionManager.save!(doc, author: user)
    expect(v2.version_number).to eq(2)

    Docsmith::VersionManager.restore!(doc, version: 1, author: user)
    expect(doc.reload.content).to eq("# Hello")

    Docsmith::VersionManager.tag!(doc, version: 1, name: "v1.0", author: user)
    expect(Docsmith::VersionTag.find_by(name: "v1.0")).not_to be_nil
  end

  it "config precedence: per-class > global > defaults" do
    Docsmith.configure { |c| c.default_debounce = 60 }
    # Article sets content_type: :markdown but not debounce → uses global 60
    config = Article.docsmith_resolved_config
    expect(config[:debounce]).to eq(60)
    expect(config[:content_type]).to eq(:markdown) # per-class wins
  end
end
