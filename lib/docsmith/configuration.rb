# frozen_string_literal: true

module Docsmith
  # DSL object for per-class docsmith_config blocks.
  # Each method call stores a key in @settings.
  # Resolution against global config happens at read time via Configuration.resolve.
  class ClassConfig
    KEYS = %i[content_field content_type auto_save debounce max_versions content_extractor].freeze

    # @return [Hash] raw settings set in this block
    attr_reader :settings

    def initialize
      @settings = {}
    end

    KEYS.each do |key|
      define_method(key) { |val| @settings[key] = val }
    end
  end

  # Global configuration object. Set via Docsmith.configure { |c| ... }.
  class Configuration
    # Gem-level defaults — final fallback in resolution order.
    # debounce stored as Integer (seconds); Duration values normalized via .to_i at resolve time.
    DEFAULTS = {
      content_field:     :body,
      content_type:      :markdown,
      auto_save:         true,
      debounce:          30,
      max_versions:      nil,
      content_extractor: nil
    }.freeze

    # Maps ClassConfig keys to their global Configuration attribute names.
    GLOBAL_KEY_MAP = {
      content_field:     :default_content_field,
      content_type:      :default_content_type,
      auto_save:         :auto_save,
      debounce:          :default_debounce,
      max_versions:      :max_versions,
      content_extractor: :content_extractor
    }.freeze

    attr_accessor :default_content_field, :default_content_type, :auto_save,
                  :default_debounce, :max_versions, :content_extractor,
                  :table_prefix, :diff_context_lines

    def initialize
      @default_content_field = DEFAULTS[:content_field]
      @default_content_type  = DEFAULTS[:content_type]
      @auto_save             = DEFAULTS[:auto_save]
      @default_debounce      = DEFAULTS[:debounce]
      @max_versions          = DEFAULTS[:max_versions]
      @content_extractor     = DEFAULTS[:content_extractor]
      @table_prefix          = "docsmith"
      @diff_context_lines    = 3
      @hooks                 = Hash.new { |h, k| h[k] = [] }
    end

    # Register a synchronous callback for a named event.
    # @param event_name [Symbol] e.g. :version_created
    # @yield [Docsmith::Events::Event]
    def on(event_name, &block)
      @hooks[event_name] << block
    end

    # @param event_name [Symbol]
    # @return [Array<Proc>]
    def hooks_for(event_name)
      @hooks[event_name]
    end
  end
end
