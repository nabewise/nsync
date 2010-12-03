require File.join(File.dirname(__FILE__), "helper")

gem "activerecord", "~> 2.3.5"
require 'active_record'
ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")
ActiveRecord::Base.send(:extend, Nsync::ActiveRecord::ClassMethods)

class TestFoo < ActiveRecord::Base
  nsync_producer :if => lambda{|o| o.should_save }
end

class TestBar < ActiveRecord::Base
  nsync_consumer

  def should_save=(val)
    val
  end
end

class TestVersion < ActiveRecord::Base
  def self.version
    scoped(:order => "id DESC").first.try(:commit_id) || "0"*40
  end

  def self.version=(commit_id)
    create(:commit_id => commit_id)
  end

  def self.previous_version
    previous_versions_raw.first.commit_id
  end

  def self.previous_versions
    previous_versions_raw.map(&:commit_id)
  end

  def self.previous_versions_raw
    scoped(:order => "id DESC", :offset => 1)
  end
end


class ActiveRecordTest < Test::Unit::TestCase
  class MyConsumer < Nsync::Consumer
    def self.config
      @config ||= Nsync::Config.new
    end
    def config
      self.class.config
    end
  end

  class MyProducer < Nsync::Producer
    def self.config
      @config ||= Nsync::Config.new
    end
    def config
      self.class.config
    end
  end

  def setup
    #Grit.debug = true
    ActiveRecord::Base.connection.create_table :test_versions, :force => true do |t|
      t.string :commit_id
      t.timestamps
    end
    ActiveRecord::Base.connection.create_table :test_foos, :force => true do |t|
      t.string :val
      t.boolean :should_save
      t.timestamps
    end

    ActiveRecord::Base.connection.create_table :test_bars, :force => true do |t|
      t.integer :source_id
      t.string :val
      t.timestamps
    end

    FileUtils.rm_rf TestRepo.repo_path
    MyProducer.config.repo_path = TestRepo.repo_path
    FileUtils.rm_rf TestRepo.repo_push_path
    Grit::Repo.init_bare(TestRepo.repo_push_path)
    MyProducer.config.repo_push_url = TestRepo.repo_push_path
    MyProducer.config.version_manager = Nsync::GitVersionManager.new(TestRepo.repo_path)
    
    MyConsumer.config.repo_url = MyProducer.config.repo_push_url
    FileUtils.rm_rf TestRepo.bare_consumer_repo_path
    MyConsumer.config.repo_path = TestRepo.bare_consumer_repo_path
    MyConsumer.config.version_manager = TestVersion
    MyConsumer.config.map_class "TestFoo", "TestBar"

    FileUtils.rm(MyProducer.config.lock_file, :force => true)

  end

  def test_integration
    @producer = MyProducer.new
    #dirty, dirty, dirty hack
    Nsync.config.producer_instance = @producer
    @consumer = MyConsumer.new

    first_foo = TestFoo.create(:val => "This should be consumed", :should_save => true)
    unsaved_foo = TestFoo.create(:val => "This should not be", :should_save => false)

    assert File.exists?(File.join(MyProducer.config.repo_path, first_foo.nsync_filename))
    assert !File.exists?(File.join(MyProducer.config.repo_path, unsaved_foo.nsync_filename))

    @producer.commit("First objects")

    @consumer.update

    assert_equal 1, TestBar.count
    assert_equal "This should be consumed", TestBar.nsync_find(first_foo.id).first.val

    unsaved_foo.update_attributes(:should_save => true, :val => "consumption time")
    
    assert File.exists?(File.join(MyProducer.config.repo_path, unsaved_foo.nsync_filename))
    
    @producer.commit("oh yeah")

    @consumer.update

    assert_equal 2, TestBar.count

    first_foo.update_attributes(:should_save => false, :val => "this is now gone")

    assert !File.exists?(File.join(MyProducer.config.repo_path, first_foo.nsync_filename))

    @producer.commit("we got rid of one")

    @consumer.update

    assert_equal 1, TestBar.count
    assert_equal unsaved_foo.id, TestBar.first.source_id

    @producer.rollback

    assert File.exists?(File.join(MyProducer.config.repo_path, first_foo.nsync_filename))

    @consumer.update

    assert_equal 2, TestBar.count

    @consumer.rollback

    assert_equal 1, TestBar.count

    @consumer.update

    assert_equal 2, TestBar.count
  end
end
