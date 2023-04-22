require './lib/target_config'

class TargetSourceConfig < TargetConfig
  attr_reader :parent_target, :config, :driver

  delegate :run!, :cleanup!, :get_log, to: :driver

  def initialize(parent_target, config)
    super

    # creating instance of the source driver class (if defined properly)
    source_type = get_config(:type)

    begin
      require "./lib/sources/#{source_type}"
      source_type_klass = "Sources::#{source_type.camelize}".constantize
    rescue => e
      raise "Unsupported source *type* definition for target #{target_ident} >> #{e}"
    end

    @driver = source_type_klass.new(self)
  end
end
