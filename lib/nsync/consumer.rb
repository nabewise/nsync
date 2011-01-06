module Nsync
  # The Nsync::Consumer is used to handle the consumption of data from an Nsync
  # repo for the entire app. It reads in the differences between the current
  # version of data in the database and the new data from the producer, finding
  # and notifying all affected classes and objects.
  #
  # Basic Usage:
  #     
  #     Nsync::Config.run do |c|
  #       # The consumer uses a read-only, bare repository (one ending in .git)
  #       # This will automatically be created if it does not exist
  #       c.repo_path = "/local/path/to/hold/data.git"
  #       # The remote repository url from which to pull data
  #       c.repo_url = "git@examplegithost:username/data.git"
  #
  #       # An object that implements the VersionManager interface 
  #       # (see Nsync::GitVersionManager) for an example
  #       c.version_manager = MyCustomVersionManager.new
  #
  #       # A lock file path to use for this app
  #       c.lock_file = "/tmp/app_name_nsync.lock"
  #
  #       # The class mapping maps from the class names of the producer classes to
  #       # the class names of their associated consuming classes. A producer can
  #       # map to one or many consumers, and a consumer can be mapped to one or many
  #       # producers. Consumer classes should implement the Consumer interface.
  #       c.map_class "RawDataPostClass", "Post"
  #       c.map_class "RawDataInfo", "Info"
  #     end
  #
  #     # Create a new consumer object, this will clone the repo if needed
  #     consumer = Nsync::Consumer.new
  #
  #     # update this app to the latest data, pulling if necessary
  #     consumer.update
  #
  #     # rollback the last change
  #     consumer.rollback
  class Consumer
    attr_accessor :repo

    # There was an issue creating or accessing the repository
    class CouldNotInitializeRepoError < RuntimeError; end
   
    # Sets the repository to the repo at config.repo_path
    #
    # If config.repo_url is set and the directory at config.repo_path does not
    # exist yet, a new bare repository will be cloned from config.repo_url
    def initialize
      unless get_or_create_repo
        raise CouldNotInitializeRepoError
      end
    end

    # Updates the data to the latest version
    #
    # If the repo has a remote origin, the latest changes will be fetched.
    #
    # NOTE: It is critical that the version_manager returns correct results
    # as this method goes from what it says is the latest commit that was loaded in
    # to HEAD.
    def update
      update_repo &&
      apply_changes(config.version_manager.version,
                    repo.head.commit.id)
    end

    # Rolls back data to the previous loaded version
    #
    # NOTE: If you rollback and then update, the 'bad' commit will then be reloaded.
    # This is primarily meant as a way to get back to a known good state quickly, while
    # the issues are fixed in the producer.
    def rollback
      apply_changes(config.version_manager.version,
                    config.version_manager.previous_version)
    end

    # @return [Nsync::Config]
    def config 
      Nsync.config
    end

    # Translates and applies the changes between commit id 'a' and commit id 'b' to
    # the datastore.  This is used internally by rollback and update. Don't use this
    # unless you absolutely know what you are doing.
    #
    # If you must call this directly, understand that 'a' should almost always be the
    # commit id of the current data that is loaded into the database. 'b' can be any
    # commit in the graph, forward or backwards.
    #
    # @param [String] a current data version commit id
    # @param [String] b new data version commit id
    def apply_changes(a, b)
      config.lock do
        config.log.info("[NSYNC] Moving Nsync::Consumer from '#{a}' to '#{b}'")
        clear_queues
        diffs = nil
        diffs = repo.diff(a, b)

        changeset = changeset_from_diffs(diffs)

        if config.ordering
          config.ordering.each do |klass|
            klass = begin
                klass.constantize
              rescue NameError => e
                config.log.warn("[NSYNC] Could not find class '#{klass}' from ordering; skipping")
                false
              end
            if klass
              changes = changeset[klass]
              if changes
                apply_changes_for_class(klass, changes)
              end
            end
          end
        else
          changeset.each do |klass, changes|
            apply_changes_for_class(klass, changes)
          end
        end
        run_after_finished
        clear_queues
        config.version_manager.version = b
      end
    end

    # Reprocesses all changes from the start of the repo to the current version
    # for the class klass, queues will not be cleared, so you can use this to
    # do powerful data reconstruction.  You can also shoot your foot off. Be
    # very careful
    def reprocess_class!(klass)
      diffs = repo.diff(first_commit, config.version_manager.version)
      changeset = changeset_from_diffs(diffs)

      changes = changeset[klass]
      if changes
        apply_changes_for_class(klass, changes)
      end
    end

    # @private
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
        {}
      end
    end

    # Adds a callback to the list of callbacks to occur after main processing
    # of the class specified by 'klass'. Can be used to handle data relations
    # between objects of the same class.
    #
    # Example:
    #     
    #     class Post
    #       def nsync_update(consumer, event_type, filename, data)
    #         #... normal data update stuff ...
    #         post = self
    #         related_post_source_ids = data['related_post_ids']
    #         consumer.after_class_finished(Post, lambda {
    #           posts = Post.all(:conditions => 
    #             {:source_id => related_post_source_ids })
    #           post.related_posts = posts
    #         })
    #       end
    #     end
    #
    # @param [Class] klass
    # @param [Proc] l
    def after_class_finished(klass, l)
      config.log.info("[NSYNC] Added callback to run after class '#{klass}'")
      @after_class_finished_queues[klass] ||= []
      @after_class_finished_queues[klass] << l
    end

    # Adds a callback to the list of callbacks to occur after main processing
    # of the class that is currently being processed. This is essentially an
    # alias for after_class_finished for the current class
    #
    # @param [Proc] l
    def after_current_class_finished(l)
      after_class_finished(@current_class_for_queue, l)
    end


    # Adds a callback to the list of callbacks to occur after all changes have
    # been applied.  This queue executes immediately prior to the current
    # version being updated
    #
    # @param [Proc] l
    def after_finished(l)
      config.log.info("[NSYNC] Added callback to run at the end of the update")
      @after_finished_queue ||= []
      @after_finished_queue << l
    end

    # Lists the configured data remotes in the repo
    def remotes
      repo.git.remote({:v => true}).split("\n").map do |line|
        line.split(/\s+/)
      end
    end

    # Gets the first commit id in the repo
    def first_commit
      self.repo.git.rev_list({:reverse => true}, "master").split("\n").first
    end

    protected
    def get_or_create_repo
      if config.local? || File.exists?(config.repo_path)
        return self.repo = Grit::Repo.new(config.repo_path)
      end

      config.lock do
        git = Grit::Git.new(config.repo_path)
        git.clone({:bare => true}, config.repo_url, config.repo_path)
        self.repo = Grit::Repo.new(config.repo_path)
        config.version_manager.version = first_commit
        return self.repo
      end
    end

    def update_repo
      return true if config.local?
      config.lock do
        repo.remote_fetch('origin')
        # from http://www.pragmatic-source.com/en/opensource/tips/automatic-synchronization-2-git-repositories
        repo.git.reset({:soft => true}, 'FETCH_HEAD')
        true
      end
    end

    def apply_changes_for_class(klass, changes)
      @current_class_for_queue = klass
      if klass.respond_to?(:nsync_find)
        changes.each do |change|
          objects = klass.nsync_find(change.id)
          if objects.empty? && change.type != :deleted
            if klass.respond_to?(:nsync_add_data)
              config.log.info("[NSYNC] Adding data #{diff_path(change.diff)} to #{klass}")
              klass.nsync_add_data(self, change.type, diff_path(change.diff), change.data)
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
      @current_class_for_queue = nil
      run_after_class_finished(klass)
    end

    def clear_queues
      config.log.info("[NSYNC] Callback queues cleared")
      @after_class_finished_queues = {}
      @after_finished_queue = []
    end

    def run_after_class_finished(klass)
      config.log.info("[NSYNC] Running callbacks for after class '#{klass}'")
      queue = @after_class_finished_queues[klass]
      if queue
        queue.each do |l|
          l.call
        end
      end
    end

    def run_after_finished
      config.log.info("[NSYNC] Running callbacks for the end of the update")
      if @after_finished_queue
        @after_finished_queue.each do |l|
          l.call
        end
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

