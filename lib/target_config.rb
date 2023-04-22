require 'active_model'

class TargetConfig
  attr_reader :parent_target, :config, :source, :target

  delegate :to_h, to: :config

  @@env_file = File.exist?('/app/.env') &&
                File.readlines('/app/.env').map { |line| line.split('=').map(&:strip) }.to_h

  def initialize(parent_target, config)
    @parent_target = parent_target
    @config = config

    # This class is also used for the sub-configs (source and target).
    # In this case the TargetConfig is initialized with the "parent"
    # TargetConfig instead of its parent Target instance.
    case parent_target
    when Target
      @context = {}
      require './lib/target_source_config'
      require './lib/target_target_config'
      @source = TargetSourceConfig.new(self, config.fetch(:source, {}))
      @target = TargetTargetConfig.new(self, config.fetch(:target, {}))
    end
  end

  def target_ident
    if parent_target.is_a?(Target)
      parent_target.ident
    else
      parent_target.target_ident
    end
  end

  def context
    if parent_target.is_a?(Target)
      @context
    else
      parent_target.context
    end
  end

  def run_scheduled?
    !run_immediately?
  end

  def run_immediately?
    get_config(:schedule_at, nil, 'immediately').downcase == 'immediately'
  end

  #
  # As all of the config values should be read from different sources,
  # we've built some logic in here to read the values:
  #
  # 1.   If the value is defined uppercase in the config, expect to read it
  #      from ENV with 2 different sub-options:
  # 1.1. If there is a .env file in the root of the project, read the value
  #      from there if present (this is for local development)
  # 1.2. If there is no .env file, read the value from the real ENV
  #
  # 2.   If the value starts with / or ./ or ../, read it from the file of the
  #      given path.
  #
  # 3.   If the value is defined lowercase in the config, use it from the
  #      config itself
  #
  # @param [Symbol] key
  # @param [String] [default_value] a default value, if no value was defined.
  # @param [String] [default_return_value] a value, if no value has been detected.
  #
  # @return [String] The detected result
  #
  def get_config(key, default_value = nil, default_return_value = nil)
    case (access_key = (config[key] || default_value)).to_s
    when /^\/|^\.\.?\//
      File.read(access_key).strip

    when /^[A-Z_]+$/
      read_env(access_key, default_return_value)

    else
      (config[key] || default_value) || default_return_value
    end
  end

  protected

  def read_env(key, default_value = nil)
    # If the key is defined, but empty then the value should be empty.
    return @@env_file[key] if @@env_file.has_key?(key) if @@env_file

    # fallback to the real ENV
    ENV[key] || default_value
  end
end
