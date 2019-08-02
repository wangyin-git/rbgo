require 'thread'

class NonBufferQueue

  def initialize
    self.enq_mutex             = Mutex.new
    self.deq_mutex             = Mutex.new
    self.enq_cond              = ConditionVariable.new
    self.deq_cond              = ConditionVariable.new
    self.resource_array        = []
    self.close_flag            = false
    self.have_enq_waiting_flag = false
    self.have_deq_waiting_flag = false
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

    if nonblock
      raise ThreadError.new unless have_deq_waiting_flag
    end

    begin
      begin
        if closed?
          raise ClosedQueueError.new
        else
          deq_mutex.synchronize do
            resource_array[0] = obj
            enq_cond.signal
            until resource_array.empty? || closed?
              self.have_enq_waiting_flag = true
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

    if nonblock
      raise ThreadError.new unless have_enq_waiting_flag
    end

    begin
      while resource_array.empty? && !closed?
        self.have_deq_waiting_flag = true
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