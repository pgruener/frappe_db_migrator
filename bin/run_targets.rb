#!/usr/bin/env ruby

require 'active_support/all'
require 'active_model'
require './lib/target'

specific_targets = ENV['SPECIFIC_TARGETS']&.split(',')&.map(&:strip)
run_immediately_ones = ActiveModel::Type::Boolean.new.cast(ENV['RUN_IMMEDIATELY_ONES'])

Target.parse_targets_from_yml_file(ENV['CONFIG_FILE'] || 'conf/targets.yml').each do |target|
  next if target.run_scheduled? && run_immediately_ones
  next if target.run_immediately? && !run_immediately_ones

  next if specific_targets && !specific_targets.include?(target.ident)

  target.run!
end
