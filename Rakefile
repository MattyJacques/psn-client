# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'

RuboCop::RakeTask.new

desc 'Validate the RBS signatures in sig/'
task :rbs do
  # spec/support/sig stands in for oauth2's types; the rest are standard libraries.
  sh 'rbs -I sig -I spec/support/sig -r logger -r net-http -r uri -r json validate'
end

task default: %i[spec rubocop rbs]
