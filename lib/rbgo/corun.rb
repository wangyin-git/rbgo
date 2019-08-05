require 'thread'
require 'fiber'
require 'sys-cpu'
require 'singleton'

module Rbgo
  module CoRun

    class Routine
      attr_accessor :error

      def alive?
        return fiber.alive? unless fiber.nil?
        true
      end

      private

      attr_accessor :args, :blk, :fiber

      def initialize(*args, new_thread: false, &blk)
        self.args = args
        self.blk  = blk
        if new_thread
          Thread.new do
            self.fiber = Fiber.new do |args|
              blk.call(*args)
            end

            begin
              while fiber.alive?
                fiber.resume(*args)
              end
            rescue Exception => ex
              self.error = ex
            end
          end

        else
          Scheduler.instance.schedule(self)
        end
      end

      def perform
        self.fiber = Fiber.new do |args|
          blk.call(*args)
        end if fiber.nil?

        if fiber.alive?
          fiber.resume(*args)
        end
        nil
      end
    end

    class Scheduler

      include Singleton
      attr_accessor :num_thread, :check_interval

      private

      attr_accessor :thread_pool
      attr_accessor :task_queue
      attr_accessor :msg_queue
      attr_accessor :supervisor_thread

      def initialize
        self.num_thread  = Sys::CPU.num_cpu || 8
        self.thread_pool = []

        self.msg_queue  = Queue.new
        self.task_queue = Queue.new

        self.check_interval = 0.1

        msg_queue << :init
        create_supervisor_thread
        generate_check_msg
      end

      # only called by supervisor thread
      def create_thread
        begin
          thread_pool << Thread.new do
            Thread.current.report_on_exception = false
            begin
              should_exit      = false
              yield_task_queue = Queue.new
              local_task_queue = Queue.new
              loop do
                task = nil
                if local_task_queue.empty?
                  task = task_queue.deq(true) rescue nil
                  if task.nil?
                    task = yield_task_queue.deq unless yield_task_queue.empty?
                    task = task_queue.deq if task.nil?
                    local_task_queue << task
                  else
                    local_task_queue << task
                    local_task_queue << yield_task_queue.deq unless yield_task_queue.empty?
                  end
                end
                task = local_task_queue.deq

                begin
                  Thread.current.thread_variable_set(:performing, true)
                  task.send :perform
                rescue Exception => ex
                  task.error = ex
                  next
                ensure
                  Thread.current.thread_variable_set(:performing, false)
                end

                if task.alive?
                  yield_task_queue << task
                end

                should_exit = Thread.current.thread_variable_get(:should_exit) &&
                  yield_task_queue.empty? &&
                  local_task_queue.empty?
                break if should_exit
              end
            ensure
              msg_queue << :thread_exit unless should_exit
            end
          end
        rescue Exception => ex
          STDERR.puts ex
        end
        nil
      end

      def create_supervisor_thread
        self.supervisor_thread = Thread.new do
          begin
            loop do
              msg = msg_queue.deq
              case msg
              when :thread_exit, :init, :check
                check_thread_pool
              end
            end
          ensure
            STDERR.puts 'supervisor thread exit'
          end
        end
        nil
      end

      def generate_check_msg
        Thread.new do
          begin
            loop do
              msg_queue << :check
              sleep check_interval
            end
          ensure
            STDERR.puts 'check generator thread exit'
          end
        end
        nil
      end

      # only called by supervisor thread
      def check_thread_pool
        temp = []
        thread_pool.each do |th|
          case th.status
          when 'run'
            temp << th
          when 'sleep'
            performing = th.thread_variable_get(:performing)
            if performing
              th.thread_variable_set(:should_exit, true)
            else
              temp << th
            end
          end
        end
        self.thread_pool = temp
        n                = num_thread - thread_pool.size
        if n > 0
          n.times { create_thread }
        elsif n < 0
          n = -n
          thread_pool.take(n).each do |th|
            th.thread_variable_set(:should_exit, true)
          end
          self.thread_pool = thread_pool.drop(n)
        end
        nil
      end

      public

      def schedule(routine)
        task_queue << routine
        nil
      end
    end
  end

  module CoRunExtensions
    refine Object do
      def go(*args, &blk)
        CoRun::Routine.new(*args, new_thread: false, &blk)
      end

      def go!(*args, &blk)
        CoRun::Routine.new(*args, new_thread: true, &blk)
      end
    end
  end
end