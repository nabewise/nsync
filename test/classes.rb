class NsyncTestFoo; end
class NsyncTestBar; end

class NsyncTestVersion
  class << self
    def version
      puts "version: #{@version}"
      @version
    end
  
    def previous_version
      @previous_version
    end
  
    def version=(id)
      puts "updated version: #{id}"
      @previous_version = @version
      @version = id
    end
  end
end

