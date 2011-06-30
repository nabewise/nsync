# The parts of ActiveSupport that we need, all shamelessly stolen
module Nsync
  module CoreExtensions
    # Upper case camelize
    def self.camelize(string)
      string.to_s.gsub(/\/(.?)/) { "::#{$1.upcase}" }.gsub(/(?:^|_)(.)/) { $1.upcase }
    end

    def self.underscore(camel_cased_word)
      camel_cased_word.to_s.gsub(/::/, '/').
        gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').
        tr("-", "_").
        downcase
    end
    
    def self.constantize(string)
      names = string.split('::')
      names.shift if names.size == 0 || names.first.size == 0

      constant = Object
      #Ruby 1.9 awesomeness
      if Module.method(:const_get).arity == 1
        names.each do |name|
          constant = constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
        end
      else
        names.each do |name|
          constant = constant.const_get(name, false) || constant.const_missing(name)
        end
      end
      constant
    end
  end
end
      

