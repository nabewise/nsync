module Nsync
  class Producer < Consumer

    def file_exists?(filename)
      File.exists?(File.join(config.repo_path, filename))
    end

    def write_file(filename, hash)
      config.cd do
        dir = File.dirname(filename)
        unless [".", "/"].include?(dir) || File.directory?(dir)
          FileUtils.mkdir_p(File.join(config.repo_path, dir))
        end

        File.open(File.join(config.repo_path, filename), "w") do |f|
          f.write( (hash.is_a?(Hash))? hash.to_json : hash )
        end
        repo.add(File.join(config.repo_path, filename))
        config.log.info("[NSYNC] Updated file '#{filename}'")
      end
      true
    end

    def remove_file(filename)
      FileUtils.rm File.join(config.repo_path, filename)
      config.log.info("[NSYNC] Removed file '#{filename}'")
    end

    def commit(message="Friendly data update")
      config.lock do
        config.cd do
          repo.commit_all(message)
          config.log.info("[NSYNC] Committed '#{message}' to repo")
        end
      end
      push
    end

    def push
      if config.remote_push?
        config.cd do
          repo.git.push({}, config.repo_push_url, "+master")
          config.log.info("[NSYNC] Pushed changes")
        end
      end
      true
    end

    def rollback
      commit_to_rollback = config.version_manager.version
      commit_to_rollback_to = config.version_manager.previous_version
      config.cd do
        repo.git.reset({:hard => true}, commit_to_rollback_to)
        apply_changes(commit_to_rollback, commit_to_rollback_to)
      end
      push
    end

    protected

    def update(*args)
      super
    end

    def apply_changes(*args)
      super
    end
    
    def get_or_create_repo
      if File.exists?(config.repo_path)
        return self.repo = Grit::Repo.new(config.repo_path)
      end

      config.lock do
        self.repo = Grit::Repo.init(config.repo_path)
        write_file(".gitignore", "")
      end
      commit("Initial Commit")
    end

    def consumer_classes_and_id_from_path(path)
      producer_class_name = File.dirname(path).camelize
      id = File.basename(path, ".json")
      classes = config.consumer_classes_for(producer_class_name)
      
      # refinement to allow the producer to consume itself
      if classes.empty?
        classes = [producer_class_name.constantize].compact
      end
      [classes, id]
    end
  end
end
