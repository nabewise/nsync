require 'rubygems'
require 'fileutils'

gem "schleyfox-grit", ">= 2.3.0.1"
require 'grit'

require 'nsync/core_extensions'

#up the timeout, as these repos can get quite large
Grit::Git.git_timeout = 60 # 1 minute should do
# 100 megabytes
Grit::Git.git_max_size = 100*1024*1024 # tweak this up for very large changesets

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
