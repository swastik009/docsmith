# frozen_string_literal: true

module Docsmith
  module Diff
    module Renderers
      # Registry for diff renderers keyed by content type string.
      # Falls back to Base for unregistered types.
      # Use Docsmith.configure { |c| c.register_diff_renderer(:html, MyRenderer) }
      # to add custom renderers at runtime.
      class Registry
        @renderers = {}

        class << self
          # @param content_type [String, Symbol]
          # @param renderer_class [Class]
          # @return [void]
          def register(content_type, renderer_class)
            @renderers[content_type.to_s] = renderer_class
          end

          # @param content_type [String, Symbol]
          # @return [Class] renderer class; defaults to Base for unregistered types
          def for(content_type)
            @renderers.fetch(content_type.to_s, Base)
          end

          # @return [Hash] copy of registered renderers
          def all
            @renderers.dup
          end

          # Resets registry to empty — for test isolation only.
          # @return [void]
          def reset!
            @renderers = {}
          end
        end
      end
    end
  end
end
