require 'thread'
require 'set'
require 'monitor'

module Channel

  module Chan

    def self.new(max = 0)
      if max <= 0
        NonBufferChan.new
      else
        BufferChan.new(max)
      end
    end

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
      nil
    end

    def notify_writable_observers
      @writable_observers.each(&:broadcast)
      nil
    end
  end

  # NonBufferChan
  #
  #
  #
  #
  #
  class NonBufferChan
    include Chan

    def initialize
      self.enq_mutex             = Mutex.new
      self.deq_mutex             = Mutex.new
      self.enq_cond              = ConditionVariable.new
      self.deq_cond              = ConditionVariable.new
      self.resource_array        = []
      self.close_flag            = false
      self.have_enq_waiting_flag = false
      self.have_deq_waiting_flag = false

      @readable_observers = Set.new
      @readable_observers.extend(MonitorMixin)
      @writable_observers = Set.new
      @writable_observers.extend(MonitorMixin)
    end

    def push(obj, nonblock = false)
      if closed?
        raise ClosedQueueError.new
      end

      if nonblock
        raise ThreadError.new unless enq_mutex.try_lock
      else
        enq_mutex.lock
      end

      begin
        if nonblock
          raise ThreadError.new unless have_deq_waiting_flag
        end
        
        begin
          if closed?
            raise ClosedQueueError.new
          else
            deq_mutex.synchronize do
              resource_array[0] = obj
              enq_cond.signal
              until resource_array.empty? || closed?
                self.have_enq_waiting_flag = true
                notify_readable_observers
                deq_cond.wait(deq_mutex)
              end
              raise ClosedQueueError.new if closed?
            end
          end
        ensure
          self.have_enq_waiting_flag = false
        end
      ensure
        enq_mutex.unlock
      end

      self
    end

    def pop(nonblock = false)
      resource = nil
      if closed?
        return [nil, false]
      end

      if nonblock
        raise ThreadError.new unless deq_mutex.try_lock
      else
        deq_mutex.lock
      end

      begin
        if nonblock
          raise ThreadError.new unless have_enq_waiting_flag
        end

        while resource_array.empty? && !closed?
          self.have_deq_waiting_flag = true
          notify_writable_observers
          enq_cond.wait(deq_mutex)
        end
        resource = resource_array.first
        resource_array.clear
        self.have_deq_waiting_flag = false
        deq_cond.signal
      ensure
        deq_mutex.unlock
      end

      [resource, !closed?]
    end

    def close
      self.close_flag = true
      enq_cond.broadcast
      deq_cond.broadcast
      notify_readable_observers
      notify_writable_observers
      self
    end

    def closed?
      close_flag
    end

    alias_method :<<, :push
    alias_method :enq, :push
    alias_method :deq, :pop
    alias_method :shift, :pop

    private

    attr_accessor :enq_mutex, :deq_mutex, :enq_cond,
                  :deq_cond, :resource_array, :close_flag,
                  :have_enq_waiting_flag, :have_deq_waiting_flag
  end




  # BufferChan
  #
  #
  #
  #
  #
  #
  class BufferChan < SizedQueue
    include Chan
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
      res = nil
      begin
        res = super(nonblock)
        notify_writable_observers
        res
      rescue ThreadError
        raise unless closed?
      end
      [res, !closed?]
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
  end


  # select_chan
  #
  #
  #
  #
  #
  #
  #
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
        cond.wait mutex
      end

    end

  ensure

    ops.each do |op|
      op.unregister(cond)
    end

  end

  # on_read
  #
  #
  #
  #
  def on_read(chan:, &blk)
    raise ArgumentError.new('chan must be a Chan') unless chan.is_a? Chan
    op = Proc.new do
      res, ok = chan.deq(true)
      if blk.nil?
        [res, ok]
      else
        blk.call(res, ok)
      end
    end
    op.define_singleton_method(:register) do |cond|
      chan.send :register, observer: cond, mode: :r
    end
    op.define_singleton_method(:unregister) do |cond|
      chan.send :unregister, observer: cond, mode: :r
    end
    op
  end

  # on_write
  #
  #
  #
  #
  #
  def on_write(chan:, obj:, &blk)
    raise ArgumentError.new('chan must be a Chan') unless chan.is_a? Chan
    op = Proc.new do
      res = chan.enq(obj, true)
      res = blk.call unless blk.nil?
      res
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