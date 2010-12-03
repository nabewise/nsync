require 'rubygems'
require 'rake'

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/*_test.rb'
  test.verbose = true
end

desc "Generate RCov test coverage and open in your browser"
task :coverage do
  require 'rcov'
  sh "rm -fr coverage"
  sh "rcov -Itest -Ilib -x \"rubygems/*,/Library/Ruby/Site/*,gems/*,rcov*\" --html test/*_test.rb"
  sh "open coverage/index.html"
end

require 'yard'
YARD::Rake::YardocTask.new

