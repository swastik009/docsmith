# frozen_string_literal: true

require "active_support/notifications"

module Docsmith
  module Events
    # Fires both AS::Notifications and callback hooks for every action.
    # Instrument name format: "#{event_name}.docsmith" (e.g. "version_created.docsmith").
    module Notifier
      # @param event_name [Symbol]
      # @param payload [Hash] keyword args forwarded to Event.new
      # @return [Docsmith::Events::Event]
      def self.instrument(event_name, **payload)
        event = Event.new(**payload)
        ActiveSupport::Notifications.instrument("#{event_name}.docsmith", payload) do
          HookRegistry.call(event_name, event)
        end
        event
      end
    end
  end
end
