# frozen_string_literal: true

require_relative "docsmith/version"
require_relative "docsmith/errors"
require_relative "docsmith/configuration"
require_relative "docsmith/versionable"

module Docsmith
  @configuration = nil

  # @return [Configuration]
  def self.configuration
    @configuration ||= Configuration.new
  end

  # Reset the global configuration (mainly used in tests)
  def self.reset_configuration!
    @configuration = nil
  end

  # Your code goes here...
end
