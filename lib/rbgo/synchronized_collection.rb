require 'monitor'
require 'set'

module Rbgo
  class SyncArray < Array
    include MonitorMixin

    def initialize(*args)
      super(*args)
    end

    Array.public_methods.each do |m|
      define_method(m) do |*args, &blk|
        synchronize { super(*args, &blk) }
      end
    end
  end

  class SyncHash < Hash
    include MonitorMixin

    def initialize(*args)
      super(*args)
    end

    Hash.public_methods.each do |m|
      define_method(m) do |*args, &blk|
        synchronize { super(*args, &blk) }
      end
    end
  end

  class SyncSet < Set
    include MonitorMixin

    def initialize(*args)
      super(*args)
    end

    Set.public_methods.each do |m|
      define_method(m) do |*args, &blk|
        synchronize { super(*args, &blk) }
      end
    end
  end
end