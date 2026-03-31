# frozen_string_literal: true

RSpec.describe Docsmith do
  it "has a version number" do
    expect(Docsmith::VERSION).not_to be nil
  end

  it "loads the gem constant" do
    expect(Docsmith::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end
end
