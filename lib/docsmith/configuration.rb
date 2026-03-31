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

    # Merge per-class settings over global config over gem defaults.
    # Resolution is at read time — global changes after class definition still apply
    # for keys the class does not override.
    # @param class_settings [Hash]
    # @param global_config [Docsmith::Configuration, nil]
    # @return [Hash] fully resolved config
    def self.resolve(class_settings, global_config)
      DEFAULTS.each_with_object({}) do |(key, default_val), result|
        global_key = GLOBAL_KEY_MAP[key]
        global_val = global_config&.public_send(global_key)

        result[key] = if class_settings.key?(key)
                        class_settings[key]
                      elsif !global_val.nil?
                        global_val
                      else
                        default_val
                      end
      end.tap { |r| r[:debounce] = r[:debounce].to_i }
    end
  end
end
