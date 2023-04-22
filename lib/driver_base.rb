class DriverBase
  attr_reader :config, :files, :logs, :status

  delegate :context, :get_config, :target_ident, to: :config

  def initialize(config)
    @config = config
    @logs = []
    @files = {}
    @status = nil
  end

  def success!
    @status = :success
  end

  def success?
    @status == :success
  end

  def log(message)
    if message.is_a?(Array)
      @logs += message
    else
      @logs << message
    end
  end

  def get_log(string_or_lines = nil, indent: 2, keep_log: false)
    string_or_lines ||= @logs
    return unless string_or_lines

    lines = string_or_lines.is_a?(String) ? string_or_lines.lines : string_or_lines

    lines.map { |line| "#{' ' * indent}#{line.sub(/\n$/, '')}" }.join("\n").tap {
      @logs = [] unless keep_log
    }
  end

  def run!
    raise "NotImplementedError: #{self.class.name}#run!"
  end

  # is called after the whole target was run to cleanup any temporary files, if needed
  def cleanup!; end
end
