require File.join(File.dirname(__FILE__), "helper")

class NsyncConsumerTest < Test::Unit::TestCase
  def setup
    NsyncTestBar.send(:nsync_consumer)
  end

  #context "Nsync::Consumer." do
end
