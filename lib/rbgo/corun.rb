require 'thread'
require 'fiber'
require 'system'
require 'singleton'
require 'openssl'
require_relative 'io_machine'
require_relative 'io_receipt'
require_relative 'once'

module Rbgo
  module CoRun
    IS_CORUN_FIBER     = :is_corun_fiber_bbc0f70e
    LOCAL_TASK_QUEUES  = :local_task_queues_bbc0f70e
    YIELD_IO_OPERATION = :yield_bbc0f70e

    def self.is_in_corun_fiber?
      !!Thread.current[IS_CORUN_FIBER]
    end

    def self.have_other_task_on_thread?
      queues = Thread.current.thread_variable_get(LOCAL_TASK_QUEUES)
      queues&.any? { |q| !q.empty? }
    end

    def self.yield_io(&blk)
      if is_in_corun_fiber?
        receipt = IOReceipt.new([:yield_io])
        CoRun::Routine.new(new_thread: true, queue_tag: :none) do
          begin
            res = blk&.call
            receipt.res = res
          ensure
            receipt.notify
          end
        end
        Fiber.yield [YIELD_IO_OPERATION, receipt]
      else
        blk.call
      end
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

    def self.read_line_from(io, sep: $/, limit: nil)
      if is_in_corun_fiber?
        return "" if limit == 0
        receipt = Scheduler.instance.io_machine.do_read_line(io, sep: sep, limit: limit)
        Fiber.yield [YIELD_IO_OPERATION, receipt]
      else
        io.readline(sep, limit)
      end
    end

    def self.read_partial_from(io, maxlen:)
      if is_in_corun_fiber?
        return "" if maxlen == 0
        receipt = Scheduler.instance.io_machine.do_read_partial(io, maxlen: maxlen)
        Fiber.yield [YIELD_IO_OPERATION, receipt]
      else
        io.readpartial(maxlen)
      end
    end

    def self.accept_from(sock)
      if is_in_corun_fiber?
        receipt = Scheduler.instance.io_machine.do_socket_accept(sock)
        Fiber.yield [YIELD_IO_OPERATION, receipt]
      else
        sock.accept
      end
    end

    def self.connect_to(sock, remote_sockaddr:)
      if is_in_corun_fiber?
        receipt = Scheduler.instance.io_machine.do_socket_connect(sock, remote_sockaddr: remote_sockaddr)
        Fiber.yield [YIELD_IO_OPERATION, receipt]
      else
        sock.connect(remote_sockaddr)
      end
    end

    def self.recv_from(sock, maxlen:, flags: 0)
      if is_in_corun_fiber?
        receipt = Scheduler.instance.io_machine.do_socket_recv(sock, maxlen: maxlen, flags: flags)
        Fiber.yield [YIELD_IO_OPERATION, receipt]
      else
        sock.recv(maxlen, flags)
      end
    end

    def self.recvmsg_from(sock, maxdatalen: nil, flags: 0, maxcontrollen: nil, opts: {})
      if is_in_corun_fiber?
        receipt = Scheduler.instance.io_machine.do_socket_recvmsg(sock, maxdatalen: maxdatalen, flags: flags, maxcontrollen: maxcontrollen, opts: opts)
        Fiber.yield [YIELD_IO_OPERATION, receipt]
      else
        sock.recvmsg(maxdatalen, flags, maxcontrollen, opts)
      end
    end

    def self.sendmsg_to(sock, mesg, flags: 0, dest_sockaddr: nil, controls: [])
      if is_in_corun_fiber?
        receipt = Scheduler.instance.io_machine.do_socket_sendmsg(sock, mesg, flags: flags, dest_sockaddr: dest_sockaddr, controls: controls)
        Fiber.yield [YIELD_IO_OPERATION, receipt]
      else
        sock.sendmsg(mesg, flags, dest_sockaddr, *controls)
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

      def initialize(*args, new_thread: false, queue_tag: :default, &blk) # :default :none :actor
        raise 'Routine must have a block' if blk.nil?
        self.args = args
        self.blk  = blk
        Scheduler.instance.schedule(self, new_thread: new_thread, queue_tag: queue_tag)
      end

      def perform
        if fiber.nil?
          self.fiber = Fiber.new do |*args|
            Thread.current[IS_CORUN_FIBER] = true
            blk.call(*args)
          end
          fiber.define_singleton_method(:transfer) do
            raise 'can not call transfer on CoRun fiber'
          end
        end

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

      def io_machine
        io_machine_init_once.do do
          @io_machine = IOMachine.new
        end
        @io_machine
      end

      def io_machine=(machine)
        @io_machine = machine
      end

      private

      attr_accessor :thread_pool
      attr_accessor :task_queues, :task_queues_mutex
      attr_accessor :msg_queue
      attr_accessor :supervisor_thread
      attr_accessor :io_machine_init_once

      def initialize
        self.num_thread = System::CPU.count rescue 8
        self.thread_pool = []

        self.msg_queue         = Queue.new
        self.task_queues       = Hash.new { |hash, key| hash[key] = Queue.new }
        self.task_queues_mutex = Mutex.new

        self.check_interval = 0.1

        self.io_machine_init_once = Once.new

        msg_queue << [:init]
        create_supervisor_thread
        generate_check_msg
      end

      # only called by supervisor thread
      def create_thread(run_for_once: false, queue_tag: :default, init_task: nil)
        begin
          thread_pool << Thread.new do
            Thread.current.report_on_exception = false
            begin
              should_exit           = false
              yield_task_queue      = Queue.new
              pending_io_task_queue = Queue.new
              local_task_queue      = Queue.new
              Thread.current.thread_variable_set(LOCAL_TASK_QUEUES, [yield_task_queue, pending_io_task_queue, local_task_queue])
              task_queue = get_queue(queue_tag)
              local_task_queue << init_task if init_task
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
                        # only pending io tasks in queue
                        receipt = task.send(:io_receipt)
                        if receipt && !receipt.done_flag
                          sleep 0.1
                        end
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
                  Rbgo.logger&.debug('Rbgo') { "#{ex.message}\n#{ex.backtrace}" }
                  next
                ensure
                  Thread.current.thread_variable_set(:performing, false)
                end

                if task.alive?
                  yield_task_queue << task
                end

                if run_for_once
                  should_exit = yield_task_queue.empty? &&
                    pending_io_task_queue.empty? &&
                    local_task_queue.empty?
                else
                  should_exit = Thread.current.thread_variable_get(:should_exit) &&
                    yield_task_queue.empty? &&
                    pending_io_task_queue.empty? &&
                    local_task_queue.empty?
                end
                break if should_exit
              end
            ensure
              msg_queue << [:thread_exit] unless should_exit
            end
          end
        rescue Exception => ex
          Rbgo.logger&.error('Rbgo') { "#{ex.message}\n#{ex.backtrace}" }
        end
        nil
      end

      def create_supervisor_thread
        self.supervisor_thread = Thread.new do
          begin
            loop do
              msg = msg_queue.deq
              case msg[0]
              when :thread_exit, :init, :check
                check_thread_pool
              when :new_thread
                task = msg[1]
                tag  = msg[2]
                create_thread(run_for_once: true, queue_tag: tag, init_task: task)
              end
            end
          ensure
            Rbgo.logger&.warn('Rbgo') { 'supervisor thread exit' }
          end
        end
        nil
      end

      def generate_check_msg
        Thread.new do
          begin
            loop do
              msg_queue << [:check]
              sleep check_interval
            end
          ensure
            Rbgo.logger&.warn('Rbgo') { 'check generator thread exit' }
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

      def get_queue(tag)
        task_queues_mutex.synchronize do
          task_queues[tag]
        end
      end

      public

      def schedule(routine, new_thread: false, queue_tag: :default)
        if new_thread
          msg_queue << [:new_thread, routine, queue_tag]
        else
          queue = get_queue(queue_tag)
          queue << routine
        end
        nil
      end
    end
  end

  CoRun.freeze

  module CoRunExtensions
    refine Object do
      def go(*args, &blk)
        CoRun::Routine.new(*args, new_thread: false, queue_tag: :default, &blk)
      end

      def go!(*args, &blk)
        CoRun::Routine.new(*args, new_thread: true, queue_tag: :none, &blk)
      end

      def have_other_task_on_thread?
        CoRun.have_other_task_on_thread?
      end

      def yield_io(&blk)
        CoRun.yield_io(&blk)
      end
    end

    refine IO do
      def yield_read(len = nil)
        CoRun.read_from(self, length: len)
      end

      def yield_read_line(sep = $/, limit = nil)
        CoRun.read_line_from(self, sep: sep, limit: limit)
      end

      def yield_read_partial(maxlen)
        CoRun.read_partial_from(self, maxlen: maxlen)
      end

      def yield_write(str)
        CoRun.write_to(self, str: str)
      end
    end

    refine Socket do
      def yield_accept
        CoRun.accept_from(self)
      end

      def yield_connect(remote_sockaddr)
        CoRun.connect_to(self, remote_sockaddr: remote_sockaddr)
      end

      def yield_recv(maxlen, flags = 0)
        CoRun.recv_from(self, maxlen: maxlen, flags: flags)
      end

      def yield_recvmsg(maxdatalen = nil, flags = 0, maxcontrollen = nil, opts = {})
        CoRun.recvmsg_from(self, maxdatalen: maxdatalen, flags: flags, maxcontrollen: maxcontrollen, opts: opts)
      end

      def yield_sendmsg(mesg, flags = 0, dest_sockaddr = nil, *controls)
        CoRun.sendmsg_to(self, mesg, flags: flags, dest_sockaddr: dest_sockaddr, controls: controls)
      end
    end

    refine OpenSSL::SSL::SSLSocket do
      def yield_accept
        CoRun.accept_from(self)
      end

      def yield_connect(remote_sockaddr)
        CoRun.connect_to(self, remote_sockaddr: remote_sockaddr)
      end

      def yield_read(len = nil)
        CoRun.read_from(self, length: len)
      end

      def yield_read_line(sep = $/, limit = nil)
        CoRun.read_line_from(self, sep: sep, limit: limit)
      end

      def yield_read_partial(maxlen)
        CoRun.read_partial_from(self, maxlen: maxlen)
      end

      def yield_write(str)
        CoRun.write_to(self, str: str)
      end
    end
  end
end