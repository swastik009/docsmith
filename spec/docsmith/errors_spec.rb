# frozen_string_literal: true

RSpec.describe "Docsmith error hierarchy" do
  it "all errors inherit from Docsmith::Error" do
    expect(Docsmith::InvalidContentField.ancestors).to include(Docsmith::Error)
    expect(Docsmith::MaxVersionsExceeded.ancestors).to include(Docsmith::Error)
    expect(Docsmith::VersionNotFound.ancestors).to include(Docsmith::Error)
    expect(Docsmith::TagAlreadyExists.ancestors).to include(Docsmith::Error)
  end

  it "Docsmith::Error inherits from StandardError" do
    expect(Docsmith::Error.ancestors).to include(StandardError)
  end

  it "can be raised and rescued as StandardError" do
    expect { raise Docsmith::InvalidContentField, "bad" }.to raise_error(StandardError, "bad")
  end
end
