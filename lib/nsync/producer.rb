module Nsync
  # The Nsync::Producer is used to tend to the repo and allow files to be
  # written out and changesets to be commited.  It is a subclass of the
  # Nsync::Consumer, which allows a Producer to consume itself.  This gives it
  # the ability to perform rollbacks and undo misstakes in that way
  #
  # Basic Usage:
  #     Nsync::Config.run do |c|
  #       # The producer uses a standard repository
  #       # This will automatically be created if it does not exist
  #       c.repo_path = "/local/path/to/hold/data"
  #       # The remote repository url will get data pushed to it
  #       c.repo_push_url = "git@examplegithost:username/data.git"
  #
  #       # This must be Nsync::GitVersionManager if you want things like
  #       # rollback to work.
  #       c.version_manager = Nsync::GitVersionManager.new
  #
  #       # A lock file path to use for this app
  #       c.lock_file = "/tmp/app_name_nsync.lock"
  #     end
  #
  #     # make some changes that get written out to the repo
  #
  #     @producer = Nsync::Producer.new
  #
  #     @producer.commit("Some nice changes for you")
  class Producer < Consumer
    # Determines whether a file at 'filename' exists in the working tree
    def file_exists?(filename)
      File.exists?(File.join(config.repo_path, filename))
    end

    # Writes a file to the repo at 'filename' with content in json from the
    # hash
    #
    # @param [String] filename path in the working tree to write to
    # @param [Hash] hash a hash that can be converted to json to be written
    # @param [Boolean] add tells whether to git add the file.  
    #   This is for internal bookkeeping files only
    def write_file(filename, hash, add=false)
      config.cd do
        dir = File.dirname(filename)
        unless [".", "/"].include?(dir) || File.directory?(dir)
          FileUtils.mkdir_p(File.join(config.repo_path, dir))
        end

        File.open(File.join(config.repo_path, filename), "w") do |f|
          f.write( (hash.is_a?(Hash))? hash.to_json : hash )
        end
        repo.add(File.join(config.repo_path, filename)) if add
        config.log.info("[NSYNC] Updated file '#{filename}'")
      end
      true
    end

    # Removes a file from the repo at 'filename'
    def remove_file(filename)
      FileUtils.rm File.join(config.repo_path, filename)
      config.log.info("[NSYNC] Removed file '#{filename}'")
    end

    def latest_changes
      diff = repo.git.native('diff', {:full_index => true})
      diff += diff_untracked_files

      if diff =~ /diff --git a/
        diff = diff.sub(/.*?(diff --git a)/m, '\1')
      else
        diff = ''
      end

      diffs = Grit::Diff.list_from_string(repo, diff)
      changeset_from_diffs(diffs)
    end

    # gets untracked files into the diff output
    # hack from http://stackoverflow.com/questions/855767/can-i-use-git-diff-on-untracked-files
    def diff_untracked_files
      response, err = repo.git.sh(<<-CMD)
        git --git-dir='#{repo.git.git_dir}' ls-files -d --others --exclude-standard  |
          while read -r i; do git --git-dir='#{repo.git.git_dir}' diff  -- /dev/null "$i"; done
      CMD
      response
    end


    # Commits and pushes the current changeset
    #
    # By default all changes in working dir are committed.
    #
    # Alternatively, specific changes can be specified in the 
    # which_changes parameter.  The format for this is {"klass" => [id,...]}
    def commit(message="Friendly data update", which_changes=:all)
      config.lock do
        config.cd do
          
          files_to_commit = []
          latest_changes.each do |klass, changes|
            which_of_class = which_changes[klass.to_s] if which_changes.is_a?(Hash)
            changes.each do |change|
              if which_changes == :all || 
                (which_of_class && which_of_class.include?(change.id))

                files_to_commit << 
                  File.join(config.repo_path, diff_path(change.diff))
              end
            end
          end
          repo.git.update_index({:add => true, :remove => true}, '--', *files_to_commit)

          repo.commit_index(message)
          config.log.info("[NSYNC] Committed '#{message}' to repo")
        end
      end
      push
    end

    # Pushes all changes to the repo_push_url
    def push
      if config.remote_push?
        config.cd do
          repo.git.push({}, config.repo_push_url, "+master")
          config.log.info("[NSYNC] Pushed changes")
        end
      end
      true
    end

    # Returns data to its state at HEAD~1 and sets HEAD to that
    # This new HEAD state is pushed to the repo_push_url.  Hooray git.
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
        write_file(".gitignore", "", true)
      end
      commit("Initial Commit")
    end

    def consumer_classes_and_id_from_path(path)
      producer_class_name = CoreExtensions.camelize(File.dirname(path))
      id = File.basename(path, ".json")
      classes = config.consumer_classes_for(producer_class_name)
      
      # refinement to allow the producer to consume itself
      if classes.empty?
        classes = [(CoreExtensions.constantize(producer_class_name) rescue nil)].compact
      end
      [classes, id]
    end
  end
end
