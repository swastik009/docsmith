# frozen_string_literal: true

require_relative "docsmith/version"
require_relative "docsmith/errors"
require_relative "docsmith/configuration"
require_relative "docsmith/versionable"

module Docsmith
  @configuration = nil

  class << self
    # @yield [Docsmith::Configuration]
    def configure
      yield configuration
    end

    # @return [Configuration]
    def configuration
      @configuration ||= Configuration.new
    end

    # Reset to defaults. Called in specs via config.before(:each).
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
