# frozen_string_literal: true

require "active_record"
require "active_support"
require "active_support/core_ext/numeric/time"
require "factory_bot"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.logger = nil

require "docsmith"

require_relative "support/schema"
require_relative "support/models"
require_relative "support/factories"

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  config.around(:each) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end

  # Reset global Docsmith config between examples so hooks/settings don't bleed.
  config.before(:each) { Docsmith.reset_configuration! }

  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = ".rspec_status"
end
