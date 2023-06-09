#!/usr/bin/env ruby

require 'active_support/all'
require './lib/target'

# Update the crontab
# File.open('/etc/crontab', 'w') do |file|
File.open('/var/spool/cron/crontabs/root', 'w') do |file|
  file << "\n\n# This section is automatically generated by frappecloud_to_pg_migrator\n\n"

  Target.parse_targets_from_yml_file(ENV['CONFIG_FILE'] || 'conf/targets.yml').each do |target|
    next if target.run_immediately?

    file << target.cron_definition.join(' ')
  end

  file << "\n\n# End of automatically generated section by frappecloud_to_pg_migrator\n\n"
end
