module Nsync
  def self.config
    @config ||= Config.new
  end

  class Config
    #required to be user specified
    attr_accessor :version_manager, :repo_path

    #optional
    attr_accessor :ordering, :repo_url, :log

    def initialize
      @class_mappings = {}
      self.log = ::Logger.new(STDOUT)
    end

    def map_class(producer_class, *consumer_classes)
      @class_mappings[producer_class] ||= []
      @class_mappings[producer_class] += consumer_classes
    end

    def version_manager
      return @version_manager if @version_manager
      raise "Must define config.version_manager"
    end

    def self.run
      yield Nsync.configuration
    end

    def local?
      !repo_url
    end

    def remote?
      !!repo_url
    end
  end
end
