require File.join(File.dirname(__FILE__), "helper")

class NsyncProducerTest < Test::Unit::TestCase
  def setup
    #Grit.debug = true
    Nsync.reset_config
    @lock_file = "/private/tmp/nsync_test_#{Process.pid}.lock"
    FileUtils.rm @lock_file, :force => true
    Nsync.config.lock_file = @lock_file
  end

  context "Initializing Producer" do
    context "when the repo already exists" do
      setup do
        @repo = TestRepo.new

        Nsync.config.repo_path = @repo.repo_path
      end

      should "not try to reinitialize it" do
        Grit::Git.any_instance.expects(:init).never
        @producer = Nsync::Producer.new
      end
    end

    context "when the repo does not exist" do
      setup do
        @repo_path = TestRepo.repo_path
        Nsync.config.repo_path = @repo_path
        FileUtils.rm_rf @repo_path
      end

      should "initialize it and make a base commit" do
        Grit::Repo.expects(:init).with(@repo_path).once
        Nsync::Producer.any_instance.expects(:write_file).with(".gitignore", "").once
        Nsync::Producer.any_instance.expects(:commit).returns(true).once
        Nsync::Producer.new
      end

      should "initialize the repo into a working state" do
        @producer = Nsync::Producer.new
        assert_equal "Initial Commit", @producer.repo.head.commit.message
        assert File.exists?(File.join(@repo_path, ".gitignore"))
      end
    end
  end

  context "Consumer methods that are probably not what you want" do
    setup do
      @repo = TestRepo.new

      Nsync.config.repo_path = @repo.repo_path
      @producer = Nsync::Producer.new
    end

    should "be protected" do
      assert_equal [], @producer.public_methods & ["update", "apply_changes"]
    end
  end


  context "Writing a file" do
    setup do
      @repo = TestRepo.new

      Nsync.config.repo_path = @repo.repo_path
      @producer = Nsync::Producer.new
    end

    context "when creating a file" do
      setup do
        @file = "foo/1.json"
        @hash = {"id" => 1, "val" => "Shazam"}
      end

      should "write the file to disk, add it to the index, but not commit" do
        @producer.repo.expects(:add).with(File.join(@repo.repo_path, @file)).once
        @producer.expects(:commit).never
        @producer.repo.expects(:commit_all).never
        @producer.write_file(@file, @hash)

        assert_equal JSON.load(File.read(File.join(@repo.repo_path, @file))),  @hash
      end
    end

    context "when modifying a file" do
      setup do
        @file = "foo/1.json"
        @hash = {"id" => 1, "val" => "Shazam"}
        @producer.write_file(@file, @hash)
      end

      should "behave just like a create" do
        new_hash = {"id" => 1, "val" => "Kaboom"}
        @producer.repo.expects(:add).with(File.join(@repo.repo_path, @file)).once
        @producer.expects(:commit).never
        @producer.write_file(@file, new_hash)

        assert_equal JSON.load(File.read(File.join(@repo.repo_path, @file))),  new_hash
      end

      context "but then removing it" do
        setup do
          @producer.remove_file(@file)
        end

        should "just be gone" do
          assert !File.exists?(File.join(@repo.repo_path, @file))
        end
      end
    end
  end

  context "Committing changes" do
    setup do
      @repo = TestRepo.new

      Nsync.config.repo_path = @repo.repo_path
      @producer = Nsync::Producer.new
    end

    should "commit all changes as well as push" do
      @msg = "Test Update"
      @producer.repo.expects(:commit_all).with(@msg).once
      @producer.expects(:push).once
      @producer.commit(@msg)
    end
  end
end
