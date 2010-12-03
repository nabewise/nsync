require File.join(File.dirname(__FILE__), 'consumer/methods')
require File.join(File.dirname(__FILE__), 'producer/methods')

module Nsync
  module ActiveRecord
    module ClassMethods
      # Makes this class an Nsync Consumer
      def nsync_consumer(opts={})
        nsync_opts = {:id_key => :source_id}.merge(opts)
        write_inheritable_attribute(:nsync_opts, nsync_opts)
        include Nsync::ActiveRecord::Consumer::InstanceMethods
      end
  
      def nsync_producer(opts={})
        nsync_opts = {:id_key => :id}.merge(opts)
        write_inheritable_attribute(:nsync_opts, nsync_opts)
        include Nsync::ActiveRecord::Consumer::InstanceMethods
        include Nsync::Producer::InstanceMethods
        include Nsync::ActiveRecord::Producer::InstanceMethods
      end
    end
  end
end
