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

  context "Pushing changes" do
    setup do
      @repo = TestRepo.new

      Nsync.config.repo_path = @repo.repo_path
      @producer = Nsync::Producer.new
    end

    context "when there is a remote push url" do
      setup do
        @push_url = "/tmp/foo/bar"
        Nsync.config.repo_push_url = @push_url
      end

      should "push changes to that" do
        @producer.repo.git.expects(:push).with({}, @push_url, "+master").once
        @producer.push
      end
    end

    context "when there is no remote push url" do
      should "not try to push" do
        @producer.repo.git.expects(:push).never
        @producer.push
      end
    end
  end

  context "Because a producer is a consumer that consumes itself" do
    setup do
      @repo = TestRepo.new

      Nsync.config.repo_path = @repo.repo_path
      @producer = Nsync::Producer.new
    end

    context "the class mapping" do
      setup do
        Nsync.config.map_class "NsyncTestBar", "NsyncTestFoo"
      end
      
      context "when unset for a class" do
        should "return the producer class" do
          assert_equal [NsyncTestFoo], 
            @producer.send(:consumer_classes_and_id_from_path, "nsync_test_foo/1.json")[0]
        end
      end

      context "when set for a class" do
        should "return a consumer class normally" do
          assert_equal [NsyncTestFoo], 
            @producer.send(:consumer_classes_and_id_from_path, "nsync_test_bar/1.json")[0]
        end
      end
    end

    context "rollback behaves quite differently" do
      setup do
        Nsync.config.version_manager = stub(:version => "bad_rev", 
                                            :previous_version => "good_rev")
      end

      should "reset from bad to good, apply changes between bad and good, and push" do
        @producer.repo.git.expects(:reset).never
        @producer.repo.git.expects(:reset).with({:hard => true}, "good_rev").once
        @producer.expects(:apply_changes).with("bad_rev", "good_rev").once
        @producer.expects(:push).once
        @producer.rollback
      end
    end
  end

  context "basic flow" do
    setup do
      @repo_path = TestRepo.repo_path
      @repo_push_url = TestRepo.bare_consumer_repo_path
      FileUtils.rm_rf @repo_path
      FileUtils.rm_rf @repo_push_url

      @remote_repo = Grit::Repo.init_bare(@repo_push_url)
      Nsync.config.repo_path = @repo_path
      Nsync.config.repo_push_url = @repo_push_url
      Nsync.config.version_manager = Nsync::GitVersionManager.new

      @producer = Nsync::Producer.new
      @repo = @producer.repo
    end

    should "work" do
      @producer.write_file("nsync_test_foo/1.json", {:id => 1, :val => "Party"})
      @producer.write_file("nsync_test_bar/2.json", {:id => 2, :val => "Study"})
      assert_equal 1, @repo.commits.size
      assert_equal 1, @remote_repo.commits.size
      assert File.exists?(File.join(@repo_path, "nsync_test_foo/1.json"))
      assert File.exists?(File.join(@repo_path, "nsync_test_bar/2.json"))
      @producer.commit("Added some files")

      assert_equal 2, @repo.commits.size
      assert_equal 2, @remote_repo.commits.size

      @producer.write_file("nsync_test_foo/2.json", {:id => 2, :val => "Rock"})
      assert File.exists?(File.join(@repo_path, "nsync_test_foo/2.json"))
      @producer.commit("And another")

      assert_equal 3, @repo.commits.size
      assert_equal 3, @remote_repo.commits.size

      @producer.remove_file("nsync_test_bar/2.json")
      assert !File.exists?(File.join(@repo_path, "nsync_test_bar/2.json"))
      @producer.commit("Remove the no-fun brigade")

      assert_equal 4, @repo.commits.size
      assert_equal 4, @remote_repo.commits.size

      NsyncTestBar.expects(:nsync_find).with('2').returns([]).once
      NsyncTestBar.expects(:nsync_add_data).once

      @producer.rollback

      assert File.exists?(File.join(@repo_path, "nsync_test_bar/2.json"))
      assert_equal 3, @repo.commits.size
      assert_equal 3, @remote_repo.commits.size

      @producer.write_file("nsync_test_bar/5.json", {:id => 5, :val => "No Fun"})
      assert File.exists?(File.join(@repo_path, "nsync_test_bar/5.json"))
      @producer.commit("Life goes on")

      assert_equal 4, @repo.commits.size
      assert_equal 4, @remote_repo.commits.size
    end
  end
end
