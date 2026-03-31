# frozen_string_literal: true

class Article < ActiveRecord::Base
  include Docsmith::Versionable

  docsmith_config do
    content_field :body
    content_type  :markdown
  end
end

class Post < ActiveRecord::Base
  include Docsmith::Versionable
  # uses all gem defaults (content_field: :body, content_type: :markdown)
end

class User < ActiveRecord::Base; end
