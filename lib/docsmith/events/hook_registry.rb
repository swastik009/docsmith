# frozen_string_literal: true

module Docsmith
  module Events
    # Calls synchronous hooks registered via Docsmith.configure { |c| c.on(:event) { } }.
    module HookRegistry
      # @param event_name [Symbol]
      # @param event [Docsmith::Events::Event]
      def self.call(event_name, event)
        Docsmith.configuration.hooks_for(event_name).each { |hook| hook.call(event) }
      end
    end
  end
end
