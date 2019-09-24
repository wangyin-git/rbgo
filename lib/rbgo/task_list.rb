require 'thread'
require 'timeout'

module Rbgo
  using CoRunExtensions

  class TaskList
    attr_accessor :last_error

    def <<(task)
      task_queue << task
      self
    end

    def add(task, timeout: nil, skip_on_exception: false)
      task_queue << proc do |last_task_result|
        begin
          Timeout::timeout(timeout) do
            task.call(last_task_result)
          end
        rescue Exception => ex
          self.last_error = ex
          raise unless skip_on_exception
        end
      end
      self
    end

    def start(arg = nil)
      start_once.do do
        _start(arg)
      end
      nil
    end

    def clear_task
      task_queue.clear
    end

    def running?
      running
    end

    def complete?
      !running? && task_queue.empty?
    end

    def wakeup
      wait_cond.signal
    end

    def wait(timeout = nil)
      wait_mutex.synchronize do
        if running?
          wait_cond.wait(wait_mutex, timeout)
        end
      end
    end

    private

    attr_accessor :task_queue, :start_once, :running, :wait_mutex, :wait_cond

    def initialize
      self.task_queue = Queue.new
      self.start_once = Once.new
      self.running    = false
      self.wait_mutex = Mutex.new
      self.wait_cond  = ConditionVariable.new
    end

    def notify
      wait_mutex.synchronize do
        self.running = false
        wait_cond.signal
      end
    end

    def _start(arg = nil)
      self.last_error = nil unless running?
      self.running    = true
      go(arg) do |last_task_result|
        begin
          task = task_queue.deq(true)
        rescue ThreadError
          notify
          self.start_once = Once.new
        else
          begin
            res = task.call(last_task_result)
          rescue Exception => ex
            self.last_error = ex
            notify
            self.start_once = Once.new
          else
            _start(res)
          end
        end
      end
    end
  end
end