module Nsync
  module ActiveRecord
    module Consumer
      module ClassMethods
        def nsync_find(ids)
          nsync_opts = read_inheritable_attribute(:nsync_opts)
          all(:conditions => {nsync_opts[:id_key] => ids})
        end

        def nsync_add_data(consumer, event_type, filename, data)
          data = data.dup
          nsync_opts = read_inheritable_attribute(:nsync_opts)
          if nsync_opts[:id_key].to_s != "id"
            data[nsync_opts[:id_key].to_s] = data.delete("id")
            create(data)
          else
            id = data.delete("id")
            obj = new(data)
            obj.id = id
            obj.save
          end
        end
      end

      module InstanceMethods
        def self.included(base)
          base.send(:extend, ClassMethods)
        end
        def nsync_update(consumer, event_type, filename, data)
          data = data.dup
          if event_type == :deleted
            destroy
          else
            nsync_opts = self.class.read_inheritable_attribute(:nsync_opts)
            if nsync_opts[:id_key].to_s != "id"
              data[nsync_opts[:id_key].to_s] = data.delete("id")
            else
              self.id = data.delete("id")
              update_attributes(data)
            end
          end
        end
      end
    end
  end
end
          
