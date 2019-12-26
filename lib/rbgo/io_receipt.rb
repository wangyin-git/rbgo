module Rbgo
  class IOReceipt
    attr_reader :registered_op, :done_flag
    attr_accessor :res

    def wait
      mutex.synchronize do
        until done_flag
          cond.wait(mutex)
        end
      end
      nil
    end

    def notify
      mutex.synchronize do
        self.done_flag = true
        cond.signal
      end
      nil
    end

    private

    attr_accessor :mutex, :cond
    attr_writer :registered_op, :done_flag

    def initialize(op)
      self.done_flag     = false
      self.mutex         = Mutex.new
      self.cond          = ConditionVariable.new
      self.registered_op = op
    end
  end
end