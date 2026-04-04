# frozen_string_literal: true

module Docsmith
  # Placeholder module for including in AR models.
  # Full implementation comes in Task 1.16.
  module Versionable
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def docsmith_config(&block)
        # Placeholder DSL - create config object and eval block in its context
        config = ClassConfig.new
        config.instance_eval(&block) if block_given?
      end
    end
  end
end
