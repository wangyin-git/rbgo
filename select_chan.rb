require 'thread'
require 'set'
require 'monitor'

module Channel
  class Chan < SizedQueue
    include Enumerable

    def each
      if block_given?
        loop do
          begin
            yield pop(true)
          rescue ThreadError
            return
          end
        end
      else
        enum_for(:each)
      end
    end

    def initialize(max)
      super(max)
      @readable_observers = Set.new
      @readable_observers.extend(MonitorMixin)
      @writable_observers = Set.new
      @writable_observers.extend(MonitorMixin)
    end

    def push(obj, nonblock = false)
      super(obj, nonblock)
      notify_readable_observers
      self
    rescue ThreadError
      raise ClosedQueueError.new if closed?
      raise
    end

    def pop(nonblock = false)
      res = super(nonblock)
      notify_writable_observers
      res
    rescue ThreadError
      raise unless closed?
    end

    def clear
      super
      notify_writable_observers
      self
    end

    def close
      super
      notify_readable_observers
      notify_writable_observers
      self
    end

    alias_method :<<, :push
    alias_method :enq, :push
    alias_method :deq, :pop
    alias_method :shift, :pop

    private

    def register(observer:, mode: :rw)
      unless observer.is_a? ConditionVariable
        return false
      end
      mode = mode.to_sym.downcase
      if mode == :rw
        @readable_observers.synchronize do
          @readable_observers.add(observer)
        end
        @writable_observers.synchronize do
          @writable_observers.add(observer)
        end
      elsif mode == :r
        @readable_observers.synchronize do
          @readable_observers.add(observer)
        end
      elsif mode == :w
        @writable_observers.synchronize do
          @writable_observers.add(observer)
        end
      else
        return false
      end
      true
    end

    def unregister(observer:, mode: :rw)
      mode = mode.to_sym.downcase
      if mode == :rw
        @readable_observers.synchronize do
          @readable_observers.delete(observer)
        end
        @writable_observers.synchronize do
          @writable_observers.delete(observer)
        end
      elsif mode == :r
        @readable_observers.synchronize do
          @readable_observers.delete(observer)
        end
      elsif mode == :w
        @writable_observers.synchronize do
          @writable_observers.delete(observer)
        end
      else
        return false
      end
      true
    end

    def notify_readable_observers
      @readable_observers.each(&:broadcast)
    end

    def notify_writable_observers
      @writable_observers.each(&:broadcast)
    end
  end

  def select_chan(*ops)
    ops.shuffle!

    mutex = Mutex.new
    cond  = ConditionVariable.new

    loop do

      ops.each do |op|
        begin
          return op.call
        rescue ThreadError
        end
      end

      return yield if block_given?

      ops.each do |op|
        op.register(cond)
      end

      mutex.synchronize do
        until ops.any?(&:ready?)
          cond.wait mutex
        end
      end

    end

  ensure

    ops.each do |op|
      op.unregister(cond)
    end

  end

  def on_read(chan:, &blk)
    raise ArgumentError.new('chan must be a Chan') unless chan.is_a? Chan
    op = Proc.new do
      res = chan.deq(true)
      res = blk.call(res) unless blk.nil?
      res
    end
    op.define_singleton_method(:ready?) do
      !chan.empty? || chan.closed?
    end
    op.define_singleton_method(:register) do |cond|
      chan.send :register, observer: cond, mode: :r
    end
    op.define_singleton_method(:unregister) do |cond|
      chan.send :unregister, observer: cond, mode: :r
    end
    op
  end

  def on_write(chan:, obj:, &blk)
    raise ArgumentError.new('chan must be a Chan') unless chan.is_a? Chan
    op = Proc.new do
      res = chan.enq(obj, true)
      res = blk.call unless blk.nil?
      res
    end
    op.define_singleton_method(:ready?) do
      chan.size < chan.max || chan.closed?
    end
    op.define_singleton_method(:register) do |cond|
      chan.send :register, observer: cond, mode: :w
    end
    op.define_singleton_method(:unregister) do |cond|
      chan.send :unregister, observer: cond, mode: :w
    end
    op
  end

  module_function :select_chan, :on_read, :on_write
end

class Object
  include Channel
end