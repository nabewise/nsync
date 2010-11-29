require File.join(File.dirname(__FILE__), "helper")

class NsyncConfigurationTest < Test::Unit::TestCase
  def setup
    @repo_path = "/foo/bar"
    @repo_origin = "http://example.com/foo/bar.git"
  end

  context "Configuration.run" do
    context "for local, non-bare configuration" do
      setup do
        Nsync::Configuration.run do |config|
          config.repo_path = @repo_path
        end
      end
  
      should "set repo_path" do
        assert_equal @repo_path, Nsync.configuration.repo_path
      end

      should "set local?" do
        assert_equal true, Nsync.configuration.local?
      end

      should "set remote?" do
        assert_equal false, Nsync.configuration.remote?
      end
    end

    context "for remote, non-bare configuration" do
      setup do
        Nsync::Configuration.run do
          config.repo_path = @repo_path
          config.repo_origin = @repo_origin
        end
      end

      should "set repo_path" do
        assert_equal @repo_path, Nsync.configuration.repo_path
      end

      should "set repo_origin" do
        assert_equal @repo_origin, Nsync.configuration.repo_origin
      end

      should "set local?" do
        assert_equal false, Nsync.configuration.local?
      end

      should "set remote?" do
        assert_equal true, Nsync.configuration.remote?
      end
    end
  end

  context "Nsync.configuration.get_consumer_classes" do
    setup do
      Nsync.configuration.map_class "NsyncTestFoo", "NsyncTestBar"
      Nsync.configuration.map_class "NsyncTestFoo", "NsyncTestFoo"
      Nsync.configuration.map_class "NsyncTestBar", "NsyncTestBar"
    end

    should "map classes according to the defined mapping in order" do
      assert_equal [NsyncTestBar, NsyncTestFoo], Nsync.configuration.get_consumer_classes("NsyncTestFoo")
      assert_equal [NsyncTestBar], Nsync.configuration.get_consumer_classes("NsyncTestBar")
    end

    should "return empty list for undefined mapping" do
      assert_equal [], Nsync.configuration.get_consumer_classes("NsyncTestBaz")
    end
  end
end
