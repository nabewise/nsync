module Nsync
  class Producer
    module InstanceMethods
      def nsync_write
        nsync_opts = self.class.read_inheritable_attribute(:nsync_opts)
        if !nsync_opts[:if] || nsync_opts[:if].call(self)
          Nsync.config.producer_instance.write_file(nsync_filename, to_nsync_hash)
        elsif Nsync.config.producer_instance.file_exists?(nsync_filename)
          nsync_destroy
        end
      end

      def nsync_destroy
        Nsync.config.producer_instance.remove_file(nsync_filename)
      end

      def nsync_filename
        nsync_opts = self.class.read_inheritable_attribute(:nsync_opts)
        File.join(self.class.to_s.underscore, "#{send(nsync_opts[:id_key])}.json")
      end
    end
  end
end
