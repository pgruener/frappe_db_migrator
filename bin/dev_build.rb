#!/usr/bin/env ruby

require 'active_support/all'
require 'active_model'

# delete (and stop) the container if it exists
%x(docker container rm -f frappe_db_migrator)

# This script is used to build the project in development mode.
%x(docker build -t frappe_db_migrator .)

envs = if File.exist?('.env')
  File.readlines('.env').map { |line|
    next if line.blank? || line.strip.starts_with?('#')

    " -e '#{line.strip}'"
  }.compact.join
end

puts ""
puts "Starting ..."
puts "  docker run [ENV variables hidden] frappe_db_migrator"
puts ""

puts %x(docker run --name frappe_db_migrator #{envs} frappe_db_migrator)
