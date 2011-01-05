require File.join(File.dirname(__FILE__), "helper")

class NsyncConfigTest < Test::Unit::TestCase
  def setup
    Nsync.reset_config
    @repo_path = "/foo/bar"
    @repo_url = "http://example.com/foo/bar.git"
  end

  context "Basic Configuration" do
    context "for local configuration" do
      setup do
        Nsync::Config.run do |config|
          config.repo_path = @repo_path
        end
      end
  
      should "set repo_path" do
        assert_equal @repo_path, Nsync.config.repo_path
      end

      should "set local?" do
        assert_equal true, Nsync.config.local?
      end

      should "set remote?" do
        assert_equal false, Nsync.config.remote?
      end
    end

    context "for remote configuration" do
      setup do
        Nsync::Config.run do |config|
          config.repo_path = @repo_path
          config.repo_url = @repo_url
        end
      end

      should "set repo_path" do
        assert_equal @repo_path, Nsync.config.repo_path
      end

      should "set repo_url" do
        assert_equal @repo_url, Nsync.config.repo_url
      end

      should "set local?" do
        assert_equal false, Nsync.config.local?
      end

      should "set remote?" do
        assert_equal true, Nsync.config.remote?
      end
    end
  end

  context "Class Mapping" do
    setup do
      Nsync.config.map_class "NsyncTestFoo", "NsyncTestBar"
      Nsync.config.map_class "NsyncTestFoo", "NsyncTestFoo"
      Nsync.config.map_class "NsyncTestBar", "NsyncTestBar"
    end

    should "map classes according to the defined mapping in order" do
      assert_equal [NsyncTestBar, NsyncTestFoo], Nsync.config.consumer_classes_for("NsyncTestFoo")
      assert_equal [NsyncTestBar], Nsync.config.consumer_classes_for("NsyncTestBar")
    end

    should "return empty list for undefined mapping" do
      assert_equal [], Nsync.config.consumer_classes_for("NsyncTestBaz")
    end
  end

  context "Lock" do
    setup do
      @lock_file = "#{TMP_DIR}/nsync_test_#{Process.pid}.lock"
      FileUtils.rm @lock_file, :force => true
      Nsync.config.lock_file = @lock_file
    end
    
    context "unlocked" do
      should "return the value of the block" do
        ret = Nsync.config.lock do
          "Success"
        end
        assert_equal "Success", ret
      end

      should "remove the lock file" do
        assert(Nsync.config.lock do
          true
        end)
        assert !File.exists?(@lock_file)
      end
    end

    context "locked" do
      setup do
        FileUtils.touch @lock_file
        #silence warnings
        Nsync.config.log = ::Logger.new("/dev/null")
      end

      should "return false" do
        ret = Nsync.config.lock do
          true
        end
        assert_equal false, ret
      end

      should "not remove the lock file" do
        assert(!Nsync.config.lock do
          true
        end)
        assert File.exists? @lock_file
      end
    end
  end

  context "Version Manager" do
    context "when unassigned" do
      setup do
        Nsync.config.version_manager = nil
      end
      should "raise an error" do
        assert_raise RuntimeError do
          Nsync.config.version_manager
        end
      end
    end

    context "when assigned" do
      setup do
        Nsync.config.version_manager = true
      end

      should "return it" do
        assert Nsync.config.version_manager
      end
    end
  end
end
