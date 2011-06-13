# The parts of ActiveSupport that we need, all shamelessly stolen
module Nsync
  module CoreExtensions
    # Upper case camelize
    def self.camelize(string)
      string.to_s.gsub(/\/(.?)/) { "::#{$1.upcase}" }.gsub(/(?:^|_)(.)/) { $1.upcase }
    end

    def self.constantize(string)
      names = string.split('::')
      names.shift if names.size == 0 || names.first.size == 0

      constant = Object
      names.each do |name|
        constant = constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
      end
      constant
    end
  end
end
      

