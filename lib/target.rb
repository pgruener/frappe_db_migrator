require 'yaml'
require 'active_support/all'
require './lib/target_config'

class Target
  attr_reader :ident, :config

  delegate :run_immediately?,
           :run_scheduled?,
           :source,
           :target,
           :context,
    to: :config

  def initialize(ident, config)
    @ident = ident
    @config = TargetConfig.new(self, config.is_a?(TargetConfig) ? config.to_h : config)
  end

  def self.parse_targets_from_yml_file(file_path)
    YAML.load_file(file_path).map { |target_ident, config|
      Target.new(target_ident, config.with_indifferent_access)
    }
  end

  def run!
    puts "Running target: #{ident}"

    puts "  Loading from source: #{source.get_config(:type)}"
    source.run!; puts source.get_log(indent: 4)

    return unless source.driver.success?

    puts "  Exporting to target: #{target.get_config(:type)}"
    target.run!; puts target.get_log(indent: 4)

    return unless target.driver.success?

    puts "\n"
    puts "  Calling cleanup on source..."
    source.cleanup!; puts source.get_log(indent: 4)

    puts "  Calling cleanup on target..."
    target.cleanup!; puts target.get_log(indent: 4)

    puts "  Done.\n\n"
  end

  def cron_definition
    return unless run_scheduled?

    [
      (config.get_config(:schedule_at)&.strip or raise "Missing *schedule_at* defined for target #{ident}"),
      # scheduling_user, # not on alpine linux
      *run_command,
      *pipes_to_stdout_and_stderr
    ]
  end

  def run_command
    res = [
      "SPECIFIC_TARGETS=#{ident}",
      '/app/bin/run_targets.rb'
    ]

    res.unshift('RUN_IMMEDIATELY_ONES=true') if run_immediately?

    res
  end

  protected

    # def scheduling_user
    #   'root'
    # end

    def pipes_to_stdout_and_stderr
      [
        '>/proc/1/fd/1',
        '2>/proc/1/fd/2'
      ]
    end
end
