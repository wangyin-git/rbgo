require 'monitor'
require 'set'

module Rbgo
  class SyncArray < Array
    @mutex = Mutex.new
    Array.public_instance_methods.each do |m|
      define_method(m) do |*args, &blk|
        SyncArray.instance_variable_get(:@mutex).synchronize { super(*args, &blk) }
      end
    end
  end

  class SyncHash < Hash
    @mutex = Mutex.new
    Hash.public_instance_methods.each do |m|
      define_method(m) do |*args, &blk|
        SyncHash.instance_variable_get(:@mutex).synchronize { super(*args, &blk) }
      end
    end
  end

  class SyncSet < Set
    @mutex = Mutex.new
    Set.public_instance_methods.each do |m|
      define_method(m) do |*args, &blk|
        SyncSet.instance_variable_get(:@mutex).synchronize { super(*args, &blk) }
      end
    end
  end
end