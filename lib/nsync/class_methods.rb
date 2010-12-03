require File.join(File.dirname(__FILE__), 'producer/methods')
module Nsync
  module ClassMethods
    # Makes this class an Nsync Consumer
    def nsync_consumer(opts={})
      nsync_opts = {:id_key => :source_id}.merge(opts)
      write_inheritable_attribute(:nsync_opts, nsync_opts)
    end

    def nsync_producer(opts={})
      nsync_opts = {:id_key => :id}.merge(opts)
      write_inheritable_attribute(:nsync_opts, nsync_opts)
      include Nsync::Producer::InstanceMethods
    end
  end
end

