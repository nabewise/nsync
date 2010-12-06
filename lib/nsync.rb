require 'rubygems'
require 'fileutils'

# just for now
gem 'activesupport', "~> 2.3.5"
require 'active_support'

gem "schleyfox-grit", ">= 2.3.0.1"
require 'grit'

#up the timeout, as these repos can get quite large
Grit::Git.git_timeout = 60 # 1 minute should do
Grit::Git.git_max_size = 100.megabytes # tweak this up for very large changesets

gem "schleyfox-lockfile", ">= 1.0.0"
require 'lockfile'

begin
  require 'yajl/json_gem'
rescue LoadError
  puts "Yajl not installed; falling back to json"
  require 'json'
end

require 'nsync/config'
require 'nsync/consumer'
require 'nsync/git_version_manager'
require 'nsync/producer'
require 'nsync/class_methods'
require 'nsync/active_record/methods.rb'
