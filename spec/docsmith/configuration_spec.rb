# frozen_string_literal: true

RSpec.describe Docsmith::Configuration do
  describe "DEFAULTS" do
    it "has expected keys and values" do
      expect(Docsmith::Configuration::DEFAULTS).to eq(
        content_field:     :body,
        content_type:      :markdown,
        auto_save:         true,
        debounce:          30,
        max_versions:      nil,
        content_extractor: nil
      )
    end

    it "is frozen" do
      expect(Docsmith::Configuration::DEFAULTS).to be_frozen
    end
  end
end

RSpec.describe Docsmith::ClassConfig do
  subject(:config) { described_class.new }

  it "starts with empty settings" do
    expect(config.settings).to eq({})
  end

  it "stores content_field setting" do
    config.content_field(:body)
    expect(config.settings[:content_field]).to eq(:body)
  end

  it "stores content_type setting" do
    config.content_type(:html)
    expect(config.settings[:content_type]).to eq(:html)
  end

  it "stores debounce accepting ActiveSupport::Duration" do
    config.debounce(60.seconds)
    expect(config.settings[:debounce]).to eq(60.seconds)
  end

  it "stores max_versions" do
    config.max_versions(10)
    expect(config.settings[:max_versions]).to eq(10)
  end

  it "stores auto_save" do
    config.auto_save(false)
    expect(config.settings[:auto_save]).to eq(false)
  end

  it "stores content_extractor proc" do
    extractor = ->(r) { r.body }
    config.content_extractor(extractor)
    expect(config.settings[:content_extractor]).to eq(extractor)
  end
end

RSpec.describe "Docsmith.configure" do
  it "yields the global configuration object" do
    Docsmith.configure { |c| c.default_content_type = :html }
    expect(Docsmith.configuration.default_content_type).to eq(:html)
  end

  it "reset_configuration! restores defaults" do
    Docsmith.configure { |c| c.default_content_type = :html }
    Docsmith.reset_configuration!
    expect(Docsmith.configuration.default_content_type).to eq(:markdown)
  end
end

RSpec.describe Docsmith::Configuration, ".resolve" do
  let(:global) { Docsmith::Configuration.new }

  it "returns gem defaults when both class and global are empty" do
    result = described_class.resolve({}, global)
    expect(result[:content_field]).to eq(:body)
    expect(result[:content_type]).to eq(:markdown)
    expect(result[:debounce]).to eq(30)
    expect(result[:auto_save]).to eq(true)
    expect(result[:max_versions]).to be_nil
  end

  it "per-class setting overrides global" do
    global.default_content_type = :html
    result = described_class.resolve({ content_type: :json }, global)
    expect(result[:content_type]).to eq(:json)
  end

  it "global setting overrides gem default" do
    global.default_content_type = :html
    result = described_class.resolve({}, global)
    expect(result[:content_type]).to eq(:html)
  end

  it "normalizes debounce ActiveSupport::Duration to Integer" do
    result = described_class.resolve({ debounce: 60.seconds }, global)
    expect(result[:debounce]).to eq(60)
    expect(result[:debounce]).to be_a(Integer)
  end

  it "per-class false for auto_save is not overridden by global true" do
    global.auto_save = true
    result = described_class.resolve({ auto_save: false }, global)
    expect(result[:auto_save]).to eq(false)
  end
end
