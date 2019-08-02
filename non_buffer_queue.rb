require 'thread'

class NonBufferQueue

  def initialize
    self.enq_mutex      = Mutex.new
    self.deq_mutex      = Mutex.new
    self.enq_cond       = ConditionVariable.new
    self.deq_cond       = ConditionVariable.new
    self.resource_array = []
    @close_flag         = false
  end

  def push(obj)
    if closed?
      raise ClosedQueueError.new
    end

    enq_mutex.synchronize do
      if closed?
        raise ClosedQueueError.new
      else
        deq_mutex.synchronize do
          resource_array[0] = obj
          enq_cond.signal
          until resource_array.empty? || closed?
            deq_cond.wait(deq_mutex)
          end
          raise ClosedQueueError.new if closed?
        end
      end
    end

  end

  def pop
    resource = nil
    if closed?
      return [nil, false]
    end

    deq_mutex.synchronize do
      while resource_array.empty? && !closed?
        enq_cond.wait(deq_mutex)
      end
      resource = resource_array.first
      resource_array.clear
      deq_cond.signal
    end

    [resource, !closed?]
  end

  def close
    @close_flag = true
    enq_cond.broadcast
    deq_cond.broadcast
  end

  def closed?
    @close_flag
  end

  alias_method :<<, :push
  alias_method :enq, :push
  alias_method :deq, :pop
  alias_method :shift, :pop

  private

  attr_accessor :enq_mutex, :deq_mutex, :enq_cond,
                :deq_cond, :resource_array

end