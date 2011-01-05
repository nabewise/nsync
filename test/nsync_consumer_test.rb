require File.join(File.dirname(__FILE__), "helper")

class NsyncConsumerTest < Test::Unit::TestCase
  def setup
    Nsync.reset_config
    #Grit.debug = true
    @lock_file = "#{TMP_DIR}/nsync_test_#{Process.pid}.lock"
    FileUtils.rm @lock_file, :force => true
    Nsync.config.lock_file = @lock_file

    Nsync.config.version_manager = stub(:version => "foo", :previous_version => "bar")
    Nsync.config.version_manager.stubs(:version=).with(is_a(String))

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
          @repo_path = "#{TMP_DIR}/nsync_non_existent_test_repo"
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
          @repo_url = "#{TMP_DIR}/nsync_non_existent_test_repo"
          @repo_path = "#{TMP_DIR}/nsync_non_existent_test_repo_consumer.git"
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

      [['local disk', nil], 
        ['github', 'git://github.com/schleyfox/test_repo.git']].each do |name, url|

        context "where the origin does exist on #{name}" do
          setup do
            @repo = TestRepo.new
            FileUtils.rm_rf @repo.bare_consumer_repo_path
  
            Nsync.config.repo_url = url || @repo.repo_path
            Nsync.config.repo_path = @repo.bare_consumer_repo_path
  
            @consumer = Nsync::Consumer.new
          end
  
          should "assign repo to a new bare repo" do
            assert @consumer.repo.is_a? Grit::Repo
            assert @consumer.repo.bare
          end
  
          should "set the origin remote" do
            origin = @consumer.remotes.detect{|r| r[0] == "origin" && r[2] == "(fetch)" }
            assert origin
            assert_equal Nsync.config.repo_url, origin[1]
          end
        end
      end  
    end
  end

  context "Updating the Consumer side" do
    setup do
      @repo = TestRepo.new
      Nsync.config.version_manager.stubs(:version => "HEAD^1")
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

      context "with ordering" do
        context "the changes" do
          setup do
            changeset = {NsyncTestFoo => ["changes"], NsyncTestBar => ["changes"]}
  
            order = states('order').starts_as('bar')
  
            Nsync.config.ordering = ["NsyncTestBar", "NsyncTestFoo"]
            @consumer.repo.expects(:diff).returns(:diffs).once
            @consumer.expects(:changeset_from_diffs).with(:diffs).returns(changeset).once
  
            @consumer.expects(:apply_changes_for_class).when(order.is('bar')).with(NsyncTestBar, ["changes"]).then(order.is('foo')).once
            @consumer.expects(:apply_changes_for_class).when(order.is('foo')).with(NsyncTestFoo, ["changes"]).then(order.is('final')).once
          end
  
          should "execute in specified order" do
            @consumer.update
          end
        end

        context "when the class in ordering is not found" do
          setup do
            Nsync.config.ordering = ["NsyncTestBlahBlah"]
            @consumer.repo.expects(:diff).returns(:diffs).once
            @consumer.expects(:changeset_from_diffs).with(:diffs).returns({}).once
            @consumer.expects(:apply_changes_for_class).never
          end

          should "not error out" do
            assert_nothing_raised do
              @consumer.update
            end
          end
        end

        context "when a NameError occurs for something other than the class" do
          setup do
            changeset = {NsyncTestFoo => ["changes"], NsyncTestBar => ["changes"]}
            Nsync.config.ordering = ["NsyncTestBar", "NsyncTestFoo"]
            @consumer.repo.expects(:diff).returns(:diffs).once
            @consumer.expects(:changeset_from_diffs).with(:diffs).returns(changeset).once
            @consumer.expects(:apply_changes_for_class).
              raises(NoMethodError, "undefined method `foo' for nil:NilClass")
          end

          should "raise the error" do
            assert_raise NoMethodError do
              @consumer.update
            end
          end
        end
      end

      context "with callbacks" do
        setup do
          Nsync.config.clear_class_mappings
          Nsync.config.map_class "Foo", "NsyncTestFoo"
          Nsync.config.map_class "Bar", "NsyncTestBar"
          Nsync.config.version_manager = NsyncTestVersion
          NsyncTestVersion.version = @repo.repo.head.commit.id

          Nsync.config.ordering = ["NsyncTestBar", "NsyncTestFoo"]
          @consumer.send(:clear_queues)
          @consumer.expects(:clear_queues).twice
        end

        should "work" do
          @repo.add_file("foo/1.json", {:id => 1, :val => "Party"})
          NsyncTestFoo.expects(:nsync_find).with('1').returns([]).once
          NsyncTestFoo.expects(:nsync_add_data).once.with(@consumer, :added, is_a(String), has_entry("val", "Party")) 
          @repo.add_file("bar/2.json", {:id => 2, :val => "Hardy"})
          @repo.commit("Added some objects")
          NsyncTestFoo.expects(:nsync_find).never
          mock_bar = mock
          mock_bar.expects(:nsync_update).once.with(@consumer, :added, is_a(String), has_entry("val", "Hardy"))
          NsyncTestBar.expects(:nsync_find).with('2').returns([mock_bar]).once


          order = states('order').starts_as('bar')

          NsyncTestFoo.expects(:from_callback).once.when(order.is('foo')).then(order.is('final'))
          mock_bar.expects(:from_callback).once.when(order.is('bar')).then(order.is('foo'))

          mock_final = mock
          mock_final.expects(:from_callback).once.when(order.is('final'))

          @consumer.after_class_finished(NsyncTestFoo, lambda { NsyncTestFoo.from_callback })
          @consumer.after_class_finished(NsyncTestBar, lambda { mock_bar.from_callback })

          @consumer.after_finished(lambda { mock_final.from_callback })

          @consumer.update
        end
      end

      context "basic flow" do
        setup do
          Nsync.config.clear_class_mappings
          Nsync.config.map_class "Foo", "NsyncTestFoo"
          Nsync.config.map_class "Bar", "NsyncTestBar"
          Nsync.config.version_manager = NsyncTestVersion
          NsyncTestVersion.version = @repo.repo.head.commit.id
        end

        should "work" do
          @repo.add_file("foo/1.json", {:id => 1, :val => "Party"})
          @repo.commit("Added one object")
          NsyncTestFoo.expects(:nsync_find).with('1').returns([]).once
          NsyncTestFoo.expects(:nsync_add_data).once.with(@consumer, :added, is_a(String), has_entry("val", "Party")) 
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
          NsyncTestBar.expects(:nsync_add_data).with(@consumer, :added, is_a(String), has_entry("val", "Moooooo")).once
          @consumer.update

          @repo.remove_file("foo/1.json")
          @repo.commit("No more party")
          mock_foo2 = mock
          mock_foo2.expects(:nsync_update).with(@consumer, :deleted, is_a(String), {}).once
          NsyncTestFoo.expects(:nsync_find).with('1').returns([mock_foo2]).once
          @consumer.update

          NsyncTestFoo.expects(:nsync_find).with('1').returns([]).once
          NsyncTestFoo.expects(:nsync_add_data).once.with(@consumer, :added, is_a(String), has_entry("val", "Party Hardest")) 

          #bring the party back
          @consumer.rollback
        end
      end
    end
  end
end
