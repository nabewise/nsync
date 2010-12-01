require File.join(File.dirname(__FILE__), "helper")

class NsyncConsumerTest < Test::Unit::TestCase
  def setup
    Nsync.reset_config
    #Grit.debug = true
    @lock_file = "/private/tmp/nsync_test_#{Process.pid}.lock"
    FileUtils.rm @lock_file, :force => true
    Nsync.config.lock_file = @lock_file

    # I think mocha is doing something evil and redefing clone
    if Grit::Git.instance_methods.include?("clone")
      Grit::Git.send(:undef_method, :clone)
    end
  end

  context "Initializing Consumer" do
    context "when the repo already exists" do
      setup do
        @repo = TestRepo.new
        FileUtils.rm_rf @repo.bare_consumer_repo_path

        Nsync.config.repo_url = @repo.repo_path
        Nsync.config.repo_path = @repo.bare_consumer_repo_path

        @consumer = Nsync::Consumer.new
      end

      should "not reclone it" do
        Grit::Git.any_instance.expects(:clone).never
        @consumer = Nsync::Consumer.new
      end
    end
        
    context "for a local repo" do
      setup do
        Nsync.config.repo_url = nil
      end

      context "that doesn't exist" do
        setup do
          @repo_path = "/private/tmp/nsync_non_existent_test_repo"
          FileUtils.rm_rf @repo_path
  
          Nsync.config.repo_path = @repo_path
        end
  
        should "raise a NoSuchPath error" do
          assert_raise Grit::NoSuchPathError do
            Nsync::Consumer.new
          end
        end
      end

      context "that does exist" do
        setup do
          @repo = TestRepo.new
          Nsync.config.repo_path = @repo.repo_path
          @consumer = Nsync::Consumer.new
        end

        should "assign it to repo" do
          assert @consumer.repo.is_a? Grit::Repo
        end
      end 
    end

    context "for a remote repo" do
      context "where the origin does not exist" do
        setup do
          @repo_url = "/private/tmp/nsync_non_existent_test_repo"
          @repo_path = "/private/tmp/nsync_non_existent_test_repo_consumer.git"
          FileUtils.rm_rf @repo_url
          FileUtils.rm_rf @repo_path

          Nsync.config.repo_url = @repo_url
          Nsync.config.repo_path = @repo_path
        end

        should "raise a NoSuchPath error" do
          assert_raise Grit::NoSuchPathError do
            Nsync::Consumer.new
          end
        end
      end

      context "where the origin does exist" do
        setup do
          @repo = TestRepo.new
          FileUtils.rm_rf @repo.bare_consumer_repo_path

          Nsync.config.repo_url = @repo.repo_path
          Nsync.config.repo_path = @repo.bare_consumer_repo_path

          @consumer = Nsync::Consumer.new
        end

        should "assign repo to a new bare repo" do
          assert @consumer.repo.is_a? Grit::Repo
          assert @consumer.repo.bare
        end
      end
    end  
  end

  context "Updating the Consumer side" do
    setup do
      @repo = TestRepo.new
      Nsync.config.version_manager = stub(:version => "HEAD^1")
      FileUtils.rm_rf @repo.bare_consumer_repo_path
    end

    context "when local" do
      setup do
        Nsync.config.repo_url = nil
        Nsync.config.repo_path = @repo.repo_path

        @consumer = Nsync::Consumer.new
        @consumer.expects(:apply_changes).once
      end

      should "not try to fetch in changes" do
        @consumer.repo.expects(:remote_fetch).never
          Grit::Git.any_instance.expects(:reset).never
        @consumer.update
      end
    end

    context "when remote" do
      setup do
        Nsync.config.repo_url = @repo.repo_path
        Nsync.config.repo_path = @repo.bare_consumer_repo_path

        @consumer = Nsync::Consumer.new
      end

      context "when updating the repo" do
        should "fetch from origin" do
          @consumer.expects(:apply_changes).once
          @consumer.repo.expects(:remote_fetch).once
          Grit::Git.any_instance.expects(:reset).once
          @consumer.update
        end
      end

      context "basic flow" do
        setup do
          Nsync.config.clear_class_mappings
          Nsync.config.map_class "Foo", "NsyncTestFoo"
          Nsync.config.map_class "Bar", "NsyncTestBar"
        end

        should "work" do
          @repo.add_file("foo/1.json", {:id => 1, :val => "Party"})
          @repo.commit("Added one object")
          NsyncTestFoo.expects(:nsync_find).with('1').returns([]).once
          NsyncTestFoo.expects(:nsync_add_data).once.with(@consumer, is_a(String), has_entry("val", "Party")) 
          @consumer.update

          @repo.add_file("bar/2.json", {:id => 2, :val => "Hardy"})
          @repo.commit("And now for the bar")
          NsyncTestFoo.expects(:nsync_find).never
          mock_bar = mock
          mock_bar.expects(:nsync_update).once.with(@consumer, :added, is_a(String), has_entry("val", "Hardy"))
          NsyncTestBar.expects(:nsync_find).with('2').returns([mock_bar]).once
          @consumer.update

          @repo.add_file("foo/1.json", {:id => 1, :val => "Party Hardest"})
          @repo.add_file("bar/3.json", {:id => 3, :val => "Moooooo"})
          @repo.commit("I changed the foo and added a bar")
          mock_foo = mock
          mock_foo.expects(:nsync_update).once.with(@consumer, :modified, is_a(String), has_entry("val", "Party Hardest"))
          NsyncTestFoo.expects(:nsync_find).with('1').returns([mock_foo]).once
          NsyncTestBar.expects(:nsync_find).with('3').returns([]).once
          NsyncTestBar.expects(:nsync_add_data).with(@consumer, is_a(String), has_entry("val", "Moooooo")).once
          @consumer.update

          @repo.remove_file("foo/1.json")
          @repo.commit("No more party")
          mock_foo2 = mock
          mock_foo2.expects(:nsync_update).with(@consumer, :deleted, is_a(String), nil).once
          NsyncTestFoo.expects(:nsync_find).with('1').returns([mock_foo2]).once
          @consumer.update

          Nsync.config.version_manager = stub(:version => 'HEAD', :previous_version => 'HEAD^1')
          NsyncTestFoo.expects(:nsync_find).with('1').returns([]).once
          NsyncTestFoo.expects(:nsync_add_data).once.with(@consumer, is_a(String), has_entry("val", "Party Hardest")) 

          #bring the party back
          @consumer.rollback
        end
      end
    end
  end
end