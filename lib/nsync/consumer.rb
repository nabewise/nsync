module Nsync
  class Consumer
    attr_accessor :repo

    class CouldNotInitializeRepoError < RuntimeError; end
    
    def initialize
      unless get_or_create_repo
        raise CouldNotInitializeRepoError
      end
    end

    def update
      update_repo &&
      apply_changes(Nsync.config.version_manager.version,
                    'HEAD')
    end

    def rollback
      apply_changes(Nsync.config.version_manager.version,
                    Nsync.config.version_manager.previous_version)
    end

    def config
      Nsync.config
    end

    def apply_changes(a, b)
      config.lock do
        Nsync.config.log.info("[NSYNC] Moving Nsync::Consumer from '#{a}' to '#{b}'")
        diffs = nil
        diffs = repo.diff(a, b)

        changeset = changeset_from_diffs(diffs)

        #p changeset
  
        if config.ordering
          config.ordering.each do |klass|
            changes = changeset[klass]
            apply_changes_for_class(klass, changes)
          end
        else
          changeset.each do |klass, changes|
            apply_changes_for_class(klass, changes)
          end
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
        @data ||= JSON.load(diff.b_blob.data)
      rescue
        nil
      end
    end

    protected
    def get_or_create_repo
      if config.local? || File.exists?(config.repo_path)
        return self.repo = Grit::Repo.new(config.repo_path)
      end

      config.lock do
        git = Grit::Git.new(config.repo_path)
        git.clone({:bare => true}, config.repo_url, config.repo_path)
        return self.repo = Grit::Repo.new(config.repo_path)
      end
    end

    def update_repo
      return true if config.local?
      config.lock do
        repo.remote_fetch('origin')
        git = Grit::Git.new(config.repo_path)
        # from http://www.pragmatic-source.com/en/opensource/tips/automatic-synchronization-2-git-repositories
        git.reset({:soft => true}, 'FETCH_HEAD')
        true
      end
    end

    def apply_changes_for_class(klass, changes)
      if klass.respond_to?(:nsync_find)
        changes.each do |change|
          objects = klass.nsync_find(change.id)
          if objects.empty? && change.type == :added
            if klass.respond_to?(:nsync_add_data)
              config.log.info("[NSYNC] Adding data #{diff_path(change.diff)} to #{klass}")
              klass.nsync_add_data(self, diff_path(change.diff), change.data)
            else
              config.log.warn("[NSYNC] Class '#{klass}' has no method nsync_add_data; skipping")
            end
          else
            objects.each do |obj|
              if obj.respond_to?(:nsync_update)
                obj.nsync_update(self, change.type, diff_path(change.diff),
                                change.data)
                config.log.info("[NSYNC] Updating from #{diff_path(change.diff)} to #{obj.inspect}")
              else
                config.log.info("[NSYNC] Object #{obj.inspect} has no method nsync_update; skipping")
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
        next h if diff_path(diff) =~ /\.gitignore$/

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
      [config.consumer_classes_for(producer_class_name), id]
    end

    def diff_path(diff)
      diff.b_path || diff.a_path
    end
  end
end

