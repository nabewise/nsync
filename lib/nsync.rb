require 'rubygems'
require 'fileutils'

# just for now
gem 'activesupport', "~> 2.3.5"
require 'active_support'

gem "schleyfox-grit", ">= 2.3.0.1"
require 'grit'

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
