require 'thread'

module Rbgo
  using CoRunExtensions

  class TaskList
    attr_accessor :last_error

    def <<(task)
      task_queue << task
    end

    def add(*tasks)
      tasks.each do |task|
        task_queue << task
      end
    end

    def start(arg = nil)
      start_once.do do
        self.last_error = nil
        self.running    = true
        go(arg) do |last_task_result|
          begin
            task = task_queue.deq(true)
            res  = task.call(last_task_result)
          rescue ThreadError
            notify
            self.start_once = Once.new
          rescue Exception => ex
            self.last_error = ex
            notify
            self.start_once = Once.new
          else
            self.start_once = Once.new
            start(res)
          end
        end
      end
      nil
    end

    def clear
      task_queue.clear
    end

    def running?
      running
    end

    def wait
      wait_mutex.synchronize do
        while running?
          wait_cond.wait(wait_mutex)
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
  end
end