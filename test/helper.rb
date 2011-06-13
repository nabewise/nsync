require File.join(File.dirname(__FILE__), "..", "lib", "nsync")

require 'rubygems'
require 'test/unit'
require 'mocha'
require 'shoulda'
require 'redgreen' unless '1.9'.respond_to?(:force_encoding)

#hack for Mac OS X
if File.directory?("/private/tmp")
  TMP_DIR = "/private/tmp"
elsif File.directory?("/tmp")
  TMP_DIR = "/tmp"
else
  raise "Couldn't find a valid tmp dir"
end

require File.join(File.dirname(__FILE__), "repo")
require File.join(File.dirname(__FILE__), "classes")


