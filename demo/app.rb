# frozen_string_literal: true

require "sinatra/base"
require "sinatra/contrib"
require "json"

# DB + models
require_relative "db/setup"
require_relative "models"
require_relative "db/seeds"

# Routes
require_relative "routes/articles"
require_relative "routes/pages"

module Demo
  class Application < Sinatra::Base
    use Articles
    use Pages

    configure do
      set :public_folder, File.expand_path("public", __dir__)
      enable :sessions
    end

    not_found { "404 — page not found" }
  end
end

# Sinatra::Base subclasses don't self-start the way Sinatra::Application does,
# so boot explicitly when this file is run directly instead of through config.ru.
Demo::Application.run!(bind: "127.0.0.1", port: 4567) if __FILE__ == $PROGRAM_NAME
