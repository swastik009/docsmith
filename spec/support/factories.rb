# frozen_string_literal: true

FactoryBot.define do
  factory :article do
    title { "Sample Article" }
    body  { "# Hello\n\nInitial content." }
  end

  factory :post do
    body { "Default post body." }
  end

  factory :user do
    name { "Test User" }
  end

  factory :docsmith_document, class: "Docsmith::Document" do
    title        { "Test Document" }
    content      { "# Hello\n\nContent here." }
    content_type { "markdown" }
  end
end
