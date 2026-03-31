# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Docsmith
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Creates the Docsmith migration and initializer."

      def create_migration
        migration_template(
          "create_docsmith_tables.rb.erb",
          "db/migrate/create_docsmith_tables.rb"
        )
      end

      def create_initializer
        template "docsmith_initializer.rb.erb", "config/initializers/docsmith.rb"
      end
    end
  end
end
