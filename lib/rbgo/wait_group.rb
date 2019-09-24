require 'thread'

module Rbgo
  class WaitGroup
    def initialize(init_count = 0)
      self.total_count = [0, init_count.to_i].max
      self.mutex       = Mutex.new
      self.cond        = ConditionVariable.new
    end

    def add(count)
      count = count.to_i
      mutex.synchronize do
        c = total_count + count
        if c < 0
          raise RuntimeError.new('WaitGroup counts < 0')
        else
          self.total_count = c
        end
      end
    end

    def done
      mutex.synchronize do
        c = total_count - 1
        if c < 0
          raise RuntimeError.new('WaitGroup counts < 0')
        else
          self.total_count = c
        end
        cond.broadcast if c == 0
      end
    end

    def wait
      mutex.synchronize do
        while total_count > 0
          cond.wait(mutex)
        end
      end
    end

    private

    attr_accessor :total_count, :mutex, :cond
  end
end