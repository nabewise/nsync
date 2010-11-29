module Nsync
  class Consumer
    attr_accessor :repo

    def initialize
      get_or_create_repo
    end

    def update
      update_repo
      apply_changes(Nsync.config.version_manager.version,
                    'HEAD')
    end

    def rollback
      apply_changes(Nsync.config.version_manager.version,
                    Nsync.config.version_manager.previous_version)

    def config
      Nsync.config
    end

    def apply_changes(a, b)
      diffs = repo.diff(a, b)

      changeset = changeset_from_diffs(diffs)

      if config.ordering
        config.ordering.each do |klass|
          changes = changeset[klass]
          apply_changes_for_class(klass, changes)
        end
      else
        changeset.each |klass, changes| do
          apply_changes_for_class(klass, changes)
        end
      end
    end


    class Change < Struct.new(:id, :diff)
      def type
        if diff.deleted_file
          :deleted
        elsif diff.new_file
          :added
        else
          :modified
        end
      end

      def data
        diff.b_blob.data
      end
    end

    protected
    def get_or_create_repo
      if config.local? || File.exists?(config.repo_path)
        return Grit::Repo.new(config.repo_path)
      end

      git = Grit::Git.new(config.repo_path)
      git.clone({:bare => true}, git.repo_url)
      return Grit::Repo.new(config.repo_path)
    end

    def update_repo
      git = Grit::Git.new(config.repo_path)
      git.pull({}, 'origin', 'master')
    end

    def apply_changes_for_class(klass, changes)
      if klass.respond_to?(:nsync_find)
        changes.each do |change|
          objects = klass.nsync_find(change.id)
          if objects.empty? && change.type == :added
            if klass.respond_to?(:nsync_add_data)
              klass.nsync_add_data(self, diff_path(change.diff), change.data)
            else
              config.log.warn("[NSYNC] Class '#{klass}' has no method nsync_add_data; skipping")
            end
          else
            objects.each do |obj|
              if obj.respond_to?(:nsync_update)
                obj.nsync_update(self, change.type, diff_path(change.diff),
                                change.data)
              else
                config.log.warn("[NSYNC] Object #{object.inspect} has no method nsync_update; skipping")
              end
            end
          end
        end
      else
        config.log.warn("[NSYNC] Consumer class '#{klass}' has no method nsync_find; skipping")
      end
    end

    def changeset_from_diffs(diffs)
      diffs.inject({}) do |h, diff|
        classes, id = consumer_classes_and_id_from_path(diff_path(diff))
        classes.each do |klass|
          h[klass] ||= []
          h[klass] << Change.new(id, diff)
        end
        h
      end
    end

    def consumer_classes_and_id_from_path(path)
      producer_class_name = File.dirname(path).camelize
      id = File.basename(path, ".json")
      [config.consumer_classes_for(class_name), id]
    end

    def diff_path(diff)
      diff.b_path || diff.a_path
    end
  end
end

