Nsync: Git based database synchronization
=========================================

Nsync allows you to keep disparate data sources synchronized for core data.
The use case this is designed to solve is when you have a data processing
system and one or many consumer facing services that depend on a canonical,
processed version of the data.  All of this is based on the power of Git.
Nsync makes no assumptions about your data stores, ORMs, or storage practices
other than that the data from the producer has something that can serve as a
unique primary key and that the consumer can be queried by a key indicating
its source.  That said, Nsync comes with extensions for ActiveRecord 2.3.x
that handle the simple case.

A NabeWise Story
----------------

Nsync was born out of our needs at NabeWise (http://nabewise.com).  We deal
with neighborhoods and cities.  Our source data consists of about 70,000
neighborhoods across the US.  We carefully curate neighborhoods for each of
our cities. Oftentimes this involves editing boundaries, making changes to
neighborhood names, or other slight adjustments to the underlying data. We
also process and refine the boundaries for display through a number of
automated processes to get the data to where we want.  This occurs in a Rails
app based on top of PostgreSQL with PostGIS.  We have to get this data to our
website, which runs on top of MySQL and Redis.  We have enough data that full
reloads from files are impractical, and we also want to handle events like
neighborhood deletion intelligently.  Nsync solves these issues.

Installation
------------

    gem install nsync

Nsync depends on two gems that I've forked, schleyfox-grit and
schleyfox-lockfile. I'm sorry, but this is how it has to be.  Nsync also
currently depends on ActiveSupport ~> 2.3.5, but I am working to remove this
dependency.

Terminology
-----------

In Nsync lingo, a producer is an object/class that creates data that will go
into a repository and propagate to consumers.  It adheres to the Producer
interface. A consumer is an object/class that takes data from the repo and
updates itself accordingly.  It adheres to the Consumer interface.  A producer
is also a consumer of itself.

Producer Usage
--------------

To start off with, you have to configure your shiny new producer app. This
configuration should happen before the producer is ever used.

    Nsync::Config.run do |c|
      # The producer uses a standard repository
      # This will automatically be created if it does not exist
      c.repo_path = "/local/path/to/hold/data"
      # The remote repository url will get data pushed to it
      c.repo_push_url = "git@examplegithost:username/data.git"
    
      # This must be Nsync::GitVersionManager if you want things like
      # rollback to work.
      c.version_manager = Nsync::GitVersionManager.new
    
      # A lock file path to use for this app
      c.lock_file = "/tmp/app_name_nsync.lock"
    end

Now you need to let your objects know the joy of Nsync. This is not strictly
necessary, but can help out. If you are using ActiveRecord, do this:

    ActiveRecord::Base.send(:extend, Nsync::ActiveRecord::ClassMethods)

If you are using something else, do this:

    YourBaseObject.send(:extend, Nsync::ClassMethods)

Now, set your data classes up as producers

    class Post < ActiveRecord::Base
      nsync_producer
    end

By default, this will write out the json-ified contents of its attributes (if
its ActiveRecord, you have to define its representation otherwise) to
"CLASS_NAME/ID.json" in the repo.

If not all of your data should be exported, you can specify an :if function

    class Post
      nsync_producer :if => lambda {|o| o.should_be_exported }
    end

After you make some data changes, you can commit and push them by doing

    producer = Nsync::Producer.new
    producer.commit("Short Message Describing Changes")

See Nsync::ClassMethods, Nsync::ActiveRecord::ClassMethods,
Nsync::Producer::InstanceMethods, and
Nsync::ActiveRecord::Producer::InstanceMethods for more information

Consumer Usage
--------------

Every good producer needs one (or many) good consumers. Again, the first step
is configuration.

The Consumer is a little less straight forward.  It requires that the classes
from the Producer side be mapped to classes on the Consumer side.  This
happens using Nsync::Config#map_class, which maps from a Producer class name
to one or many Consumer classes.

It also requires that Nsync::Config#version_manager is set to a class or
instance that conforms to the VersionManager interface. This is probably a
class on top of a database that stores versions (by commit id) as they are
loaded into the system, such that the current version and all previous
versions can be easily accessed. The ActiveRecord integration tests
demonstrate this.

    Nsync::Config.run do |c|
      # The consumer uses a read-only, bare repository (one ending in .git)
      # This will automatically be created if it does not exist
      c.repo_path = "/local/path/to/hold/data.git"
      # The remote repository url from which to pull data
      c.repo_url = "git@examplegithost:username/data.git"
    
      # An object that implements the VersionManager interface 
      # (see Nsync::GitVersionManager) for an example
      c.version_manager = MyCustomVersionManager.new
    
      # A lock file path to use for this app
      c.lock_file = "/tmp/app_name_nsync.lock"
    
      # The class mapping maps from the class names of the producer classes to
      # the class names of their associated consuming classes. A producer can
      # map to one or many consumers, and a consumer can be mapped to one or many
      # producers. Consumer classes should implement the Consumer interface.
      c.map_class "RawDataPostClass", "Post"
      c.map_class "RawDataInfo", "Info"
    end

Now you should let your classes know about the Nsync way.If you are using
ActiveRecord, do this:

    ActiveRecord::Base.send(:extend, Nsync::ActiveRecord::ClassMethods)

If you are using something else, do this:

    YourBaseObject.send(:extend, Nsync::ClassMethods)

Now it's time to let your objects know that they are consumers

    class Post < ActiveRecord::Base
      nsync_consumer
    end

You can (and probably should) override all or some of the default methods in
the Consumer interface.  By default, it basically just attempts to copy hash
from the file into the consuming database.  If your object has any relations,
this will probably fail tragically. A better Post class would be

    class Post < ActiveRecord::Base

      nsync_consumer

      def self.nsync_add_data(consumer, event_type, filename, data)
        post = new
        post.source_id = data['id']
        post.nsync_update(consumer, event_type, filename, data)
      end

      def nsync_update(consumer, event_type, filename, data)
        if event_type == :deleted
          destroy
        else
          self.author = Author.nsync_find(data['author_id']).first
          self.content = data['content']
          
          related_post_source_ids = data['related_post_ids']
          post = self

          consumer.after_current_class_finished(lambda {
            post.related_posts = Post.all(:conditions => {:source_id =>
              related_post_source_ids})
          })

          self.save
        end
      end
    end

This also demonstrates how to add callbacks to queues.

You can update from the repo like so:

    consumer = Nsync::Consumer.new
    consumer.update






