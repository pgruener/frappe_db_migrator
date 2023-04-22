require './lib/target_config'

class TargetTargetConfig < TargetConfig
  attr_reader :parent_target, :config, :driver

  delegate :run!, :cleanup!, :get_log, to: :driver

  def initialize(parent_target, config)
    super

    # creating instance of the target driver class (if defined properly)
    target_type = get_config(:type)

    begin
      require "./lib/targets/#{target_type}"
      target_type_klass = "Targets::#{target_type.camelize}".constantize
    rescue => e
      raise "Unsupported target *type* definition for target #{target_ident} >> #{e}"
    end

    @driver = target_type_klass.new(self)
  end
end
