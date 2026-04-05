# frozen_string_literal: true

require "active_record"
require "active_support"
require "active_support/core_ext/numeric/time"
require "active_support/notifications"

require_relative "docsmith/version"
require_relative "docsmith/errors"
require_relative "docsmith/configuration"
require_relative "docsmith/events/event"
require_relative "docsmith/events/hook_registry"
require_relative "docsmith/events/notifier"
require_relative "docsmith/document"
require_relative "docsmith/document_version"
require_relative "docsmith/version_tag"
require_relative "docsmith/auto_save"
require_relative "docsmith/version_manager"
require_relative "docsmith/versionable"
require_relative "docsmith/diff"
require_relative "docsmith/diff/renderers"
require_relative "docsmith/diff/renderers/base"
require_relative "docsmith/diff/renderers/registry"
require_relative "docsmith/diff/result"
require_relative "docsmith/diff/engine"
require_relative "docsmith/rendering/html_renderer"
require_relative "docsmith/rendering/json_renderer"
require_relative "docsmith/comments/comment"

module Docsmith
  class << self
    # @yield [Docsmith::Configuration]
    def configure
      yield configuration
    end

    # @return [Docsmith::Configuration]
    def configuration
      @configuration ||= Configuration.new
    end

    # Reset to gem defaults. Call in specs via config.before(:each).
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
