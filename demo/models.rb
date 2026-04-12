# frozen_string_literal: true

require "docsmith"

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
