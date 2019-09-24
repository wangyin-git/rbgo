# frozen_string_literal: true

require_relative 'reentrant_mutex'
module Rbgo
  class RWMutex

    def initialize
      @lock_count = Hash.new(0)
      @mutex      = ReentrantMutex.new
      @cond       = ConditionVariable.new
      @status     = :unlocked
    end

    def owned?
      @mutex.synchronize do
        @lock_count.key? Thread.current
      end
    end

    def locked?
      @mutex.synchronize do
        if @lock_count.empty?
          return false
        else
          return true
        end
      end
    end

    def synchronize_r
      raise ThreadError, 'Must be called with a block' unless block_given?

      begin
        lock_r
        yield
      ensure
        unlock
      end
    end

    def synchronize_w
      raise ThreadError, 'Must be called with a block' unless block_given?

      begin
        lock_w
        yield
      ensure
        unlock
      end
    end

    private

    def lock_r
      @mutex.synchronize do
        case @status
        when :locked_for_write
          until @status == :unlocked || @status == :locked_for_read || owned?
            @cond.wait(@mutex)
          end
        end
        tmp_status                  = @status
        @status                     = :locked_for_read
        @lock_count[Thread.current] += 1
        if owned? && tmp_status == :locked_for_write
          @cond.broadcast
        end
        return self
      end
    end

    def lock_w
      @mutex.synchronize do
        until @status == :unlocked || (owned? && @status == :locked_for_write)
          @cond.wait(@mutex)
        end
        @status                     = :locked_for_write
        @lock_count[Thread.current] += 1
        return self
      end
    end

    def unlock
      @mutex.synchronize do
        if owned?
          @lock_count[Thread.current] -= 1
          @lock_count.delete(Thread.current) if @lock_count[Thread.current] == 0
          if @lock_count.empty?
            @status = :unlocked
            @cond.broadcast
          end
        end
      end
    end
  end
end