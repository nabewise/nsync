module Nsync
  class GitVersionManager
    def repo
      # if the repo is not ready, lets just hope it works
      @repo ||= Grit::Repo.new(Nsync.config.repo_path) rescue nil
    end

    def version
      repo.head.commit.id if repo
    end

    def previous_version
      previous_versions[0]
    end

    def previous_versions
      repo.commits("master", 10, 1).map(&:id) if repo
    end
  end
end

