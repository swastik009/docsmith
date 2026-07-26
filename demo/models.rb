# frozen_string_literal: true

require "docsmith"
require "rails-html-sanitizer"

class User < ActiveRecord::Base; end

class Article < ActiveRecord::Base
  include Docsmith::Versionable

  docsmith_config do
    content_field :body
    content_type  :markdown
    auto_save     false   # manual control in the demo
    max_versions  nil
  end
end

# An HTML-content document, used by /pages to demonstrate html_sanitizer.
class Page < ActiveRecord::Base
  include Docsmith::Versionable

  docsmith_config do
    content_field :body
    content_type  :html
    auto_save     false
    max_versions  nil
  end
end

# Stored HTML is untrusted, so Docsmith escapes it unless you supply a sanitizer.
# The gem ships none on purpose — a safe one needs a real HTML parser, and that
# would cost it the zero-system-dependency guarantee.
#
# This demo installs rails-html-sanitizer explicitly to show the recommended
# setup. A Rails app already has it through ActionView and needs no extra gem.
SAFE_LIST_SANITIZER = Rails::HTML5::SafeListSanitizer.new

Docsmith.configure do |config|
  config.html_sanitizer = ->(html) { SAFE_LIST_SANITIZER.sanitize(html) }
end
