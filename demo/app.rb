# frozen_string_literal: true

require "sinatra/base"
require "sinatra/contrib"
require "json"

# DB + models
require_relative "db/setup"
require_relative "models"

# Routes
require_relative "routes/articles"

module Demo
  class Application < Sinatra::Base
    use Articles

    configure do
      set :public_folder, File.expand_path("public", __dir__)
      enable :sessions
    end

    not_found { "404 — page not found" }
  end
end
