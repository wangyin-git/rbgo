require 'monitor'
require 'set'

module Rbgo
  class Array
    def self.[](*args)
      Array.new(::Array.[](*args))
    end

    def self.try_convert(obj)
      a = ::Array.try_convert(obj)
      a.nil? ? nil : Array.new(a)
    end

    def initialize(*args, &blk)
      @a = ::Array.new(*args, &blk)
      @a.extend(MonitorMixin)
    end

    ::Array.public_instance_methods.each do |m|
      define_method(m) do |*args, &blk|
        @a.synchronize do
          @a.send m, *args, &blk
        end
      end
    end
  end

  class Hash
    def self.[](*args)
      h = Hash.new
      h.instance_eval do
        @h = ::Hash.[](*args)
        @h.extend(MonitorMixin)
      end
    end

    def self.try_convert(obj)
      h = ::Hash.try_convert(obj)
      h.nil? ? nil : Hash.[](h)
    end

    def initialize(*args, &blk)
      @h = ::Hash.new(*args, &blk)
      @h.extend(MonitorMixin)
    end

    ::Hash.public_instance_methods.each do |m|
      define_method(m) do |*args, &blk|
        @h.synchronize do
          @h.send m, *args, &blk
        end
      end
    end
  end

  class Set
    def self.[](*args)
      Set.new(::Set.[](*args))
    end

    def initialize(enum = nil)
      @s = ::Set.new(enum)
      @s.extend(MonitorMixin)
    end

    ::Set.public_instance_methods.each do |m|
      define_method(m) do |*args, &blk|
        @s.synchronize do
          @s.send m, *args, &blk
        end
      end
    end
  end
end