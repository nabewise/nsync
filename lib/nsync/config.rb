module Nsync
  def self.config
    @config ||= Config.new
  end

  def self.reset_config
    @config = nil
  end

  class Config
    #required to be user specified
    attr_accessor :version_manager, :repo_path

    #optional
    attr_accessor :ordering, :repo_url, :repo_push_url, :log, :lock_file, 
      :producer_instance

    include Lockfile

    def initialize
      clear_class_mappings
      self.log = ::Logger.new(STDERR)
      self.lock_file = "/tmp/nsync.lock"
    end

    def lock
      ret = nil
      success = with_lock_file(lock_file) do
        ret = yield
      end
      if success != false
        return ret
      else
        log.error("[NSYNC] Could not obtain lock!; exiting")
        return false
      end
    end

    def cd
      old_pwd = FileUtils.pwd
      begin
        FileUtils.cd repo_path
        yield
      ensure
        FileUtils.cd old_pwd
      end
    end


    def map_class(producer_class, *consumer_classes)
      @class_mappings[producer_class] ||= []
      @class_mappings[producer_class] += consumer_classes
    end

    def clear_class_mappings
      @class_mappings = {}
    end

    def consumer_classes_for(producer_class)
      Array(@class_mappings[producer_class]).map do |klass|
        begin
          klass.constantize
        rescue NameError => e
          log.error(e.inspect)
          log.warn("[NSYNC] Could not find class '#{klass}'; skipping")
          nil
        end
      end.compact
    end

    def version_manager
      return @version_manager if @version_manager
      raise "Must define config.version_manager"
    end

    def producer_instance
      @producer_instance ||= Nsync::Producer.new
    end

    def self.run
      yield Nsync.config
    end

    def local?
      !repo_url
    end

    def remote?
      !!repo_url
    end

    def remote_push?
      !!repo_push_url
    end
  end
end
