class TestRepo
  attr_accessor :repo

  def initialize(opts={})
    FileUtils.rm_rf(repo_path)
    self.repo = Grit::Repo.init(repo_path)
    add_file(".gitignore", "")
    commit("Initial Commit")
  end

  def cd
    old_pwd = FileUtils.pwd
    begin
      FileUtils.cd repo_path
      yield
    ensure
      FileUtils.cd old_pwd
    end
  end

  def repo_path
    self.class.repo_path
  end

  def self.repo_path
    "#{TMP_DIR}/nsync_test_repo_#{Process.pid}"
  end

  def bare_consumer_repo_path
    self.class.bare_consumer_repo_path
  end

  def self.bare_consumer_repo_path
    "#{repo_path}_consumer.git"
  end

  def self.repo_push_path
    "#{repo_path}_producer_push.git"
  end

  def add_file(filename, content, add=true)
    cd do
      dir = File.dirname(filename)
      if ![".", "/"].include?(dir) && !File.exists?(dir)
        FileUtils.mkdir_p(File.join(repo_path, dir))
      end
      File.open(File.join(repo_path, filename), "w") do |f|
        f.write((content.is_a?(Hash))? content.to_json : content)
      end
      repo.add(File.join(repo_path, filename)) if add
    end
  end

  def remove_file(filename)
    FileUtils.rm File.join(repo_path, filename)
  end

  def commit(message)
    cd do
      repo.commit_all(message)
    end
  end

end
