# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Docsmith
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Creates the Docsmith migration and initializer."

      # NOTE: do not name this `create_migration`. Rails::Generators::Migration
      # defines create_migration(destination, data, config) and migration_template
      # calls it internally, so a same-named zero-arg action method shadows it and
      # the generator dies with "wrong number of arguments (given 3, expected 0)".
      # That is what happened in 0.1.0.
      def create_migration_file
        migration_template(
          "create_docsmith_tables.rb.erb",
          "db/migrate/create_docsmith_tables.rb"
        )
      end

      def create_initializer
        template "docsmith_initializer.rb.erb", "config/initializers/docsmith.rb"
      end

      private

      # Column type for JSON payload columns, chosen per adapter.
      # PostgreSQL gets :jsonb (indexable); every other adapter gets :json,
      # which MySQL and SQLite both support and which casts to Hash the same way.
      # Reads the db config rather than the connection so generation works offline.
      #
      # Matches /postg/ rather than a "postgresql" prefix so PostgreSQL-derived
      # adapters (postgis, postgresql_makara) still get jsonb.
      #
      # @return [String]
      def json_column_type
        ActiveRecord::Base.connection_db_config.adapter.to_s.match?(/postg/i) ? "jsonb" : "json"
      rescue StandardError
        "json"
      end
    end
  end
end
