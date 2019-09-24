module Rbgo
  class Semaphore
    def initialize(count)
      count = count.to_i
      raise 'count must be positive' if count <= 0
      @mutex = Mutex.new
      @cond  = ConditionVariable.new
      @count = count
    end

    def available_permits
      @mutex.synchronize do
        return @count
      end
    end

    def acquire(permits = 1)
      raise 'Must be called with a block' unless block_given?

      begin
       ok = _acquire(permits)
        yield
      ensure
        release(permits) if ok
      end
    end

    def acquire_all
      raise 'Must be called with a block' unless block_given?

      begin
        permits = drain_permits
        yield
      ensure
        release(permits)
      end
    end

    def try_acquire(permits = 1)
      raise 'Must be called with a block' unless block_given?

      begin
        ok = _try_acquire(permits)
        yield if ok
      ensure
        release(permits) if ok
      end
      return ok
    end

    def release(permits = 1)
      permits = permits.to_i
      raise 'permits must be positive' if permits <= 0
      @mutex.synchronize do
        @count += permits
        @cond.broadcast
      end
      self
    end

    private

    def _acquire(permits = 1)
      permits = permits.to_i
      raise 'permits must be positive' if permits <= 0
      @mutex.synchronize do
        while @count - permits < 0
          @cond.wait(@mutex)
        end
        @count -= permits
        return self
      end
    end

    def drain_permits
      @mutex.synchronize do
        while @count <= 0
          @cond.wait(@mutex)
        end
        tmp_count = @count
        @count = 0
        return tmp_count
      end
    end

    def _try_acquire(permits = 1)
      permits = permits.to_i
      raise 'permits must be positive' if permits <= 0
      @mutex.synchronize do
        if @count - permits < 0
          return false
        else
          @count -= permits
          return true
        end
      end
    end
  end
end