require 'thread'
require 'fiber'
require 'system'
require 'singleton'
require_relative 'io_machine'

module Rbgo
  module CoRun
    IS_CORUN_FIBER     = :is_corun_fiber_bbc0f70e
    YIELD_IO_OPERATION = :yield_bbc0f70e

    def self.is_in_corun_fiber?
      !!Thread.current[IS_CORUN_FIBER]
    end

    def self.read_from(io, length: nil)
      if is_in_corun_fiber?
        return "" if length == 0
        receipt = Scheduler.instance.io_machine.do_read(io, length: length)
        Fiber.yield [YIELD_IO_OPERATION, receipt]
      else
        io.read(length)
      end
    end

    def self.write_to(io, str:)
      if is_in_corun_fiber?
        receipt = Scheduler.instance.io_machine.do_write(io, str: str)
        Fiber.yield [YIELD_IO_OPERATION, receipt]
      else
        io.write(str)
      end
    end

    class Routine
      attr_accessor :error

      def alive?
        return fiber.alive? unless fiber.nil?
        true
      end

      private

      attr_accessor :args, :blk, :fiber, :io_receipt

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
              STDERR.puts ex
            end
          end

        else
          Scheduler.instance.schedule(self)
        end
      end

      def perform
        self.fiber = Fiber.new do |args|
          Thread.current[IS_CORUN_FIBER] = true
          blk.call(*args)
        end if fiber.nil?

        if fiber.alive?
          if io_receipt.nil?
            obj = fiber.resume(*args)
          else
            if io_receipt.done_flag
              obj = fiber.resume(io_receipt.res)
            else
              return nil
            end
          end
          if obj.is_a?(Array) &&
            obj.size == 2 &&
            obj[0] == YIELD_IO_OPERATION &&
            obj[1].is_a?(IOReceipt)
            self.io_receipt = obj[1]
          else
            self.io_receipt = nil
          end
        end
        nil
      end
    end

    class Scheduler

      include Singleton
      attr_accessor :num_thread, :check_interval, :io_machine

      private

      attr_accessor :thread_pool
      attr_accessor :task_queue
      attr_accessor :msg_queue
      attr_accessor :supervisor_thread

      def initialize
        self.num_thread = System::CPU.count rescue 8
        self.thread_pool = []

        self.msg_queue  = Queue.new
        self.task_queue = Queue.new

        self.check_interval = 0.1

        self.io_machine = IOMachine.new

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
              should_exit           = false
              yield_task_queue      = Queue.new
              pending_io_task_queue = Queue.new
              local_task_queue      = Queue.new
              loop do
                task = nil
                if local_task_queue.empty?
                  task = task_queue.deq(true) rescue nil
                  if task.nil?
                    task = yield_task_queue.deq unless yield_task_queue.empty?
                    if task.nil?
                      task = pending_io_task_queue.deq unless pending_io_task_queue.empty?
                      if task.nil?
                        task = task_queue.deq
                      else
                        sleep 0.1 # only pending io tasks in queue
                      end
                    else
                      receipt = task.send(:io_receipt)
                      if receipt
                        pending_io_task_queue << task unless receipt.done_flag
                        next
                      end
                    end
                  end

                  local_task_queue << task
                  local_task_queue << yield_task_queue.deq unless yield_task_queue.empty?
                  local_task_queue << pending_io_task_queue.deq unless pending_io_task_queue.empty?

                end

                task = local_task_queue.deq

                begin
                  Thread.current.thread_variable_set(:performing, true)
                  task.send :perform
                rescue Exception => ex
                  task.error = ex
                  STDERR.puts(ex)
                  next
                ensure
                  Thread.current.thread_variable_set(:performing, false)
                end

                if task.alive?
                  yield_task_queue << task
                end

                should_exit = Thread.current.thread_variable_get(:should_exit) &&
                  yield_task_queue.empty? &&
                  pending_io_task_queue.empty? &&
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

  CoRun.freeze

  module CoRunExtensions
    refine Object do
      def go(*args, &blk)
        CoRun::Routine.new(*args, new_thread: false, &blk)
      end

      def go!(*args, &blk)
        CoRun::Routine.new(*args, new_thread: true, &blk)
      end
    end

    refine IO do
      def yield_read(len = nil)
        CoRun.read_from(self, length: len)
      end

      def yield_write(str)
        CoRun.write_to(self, str: str)
      end
    end
  end
end