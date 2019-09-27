require 'thread'

module Rbgo
  module Channel
    module Chan
      include Enumerable

      def each
        if block_given?
          loop do
            obj, ok = pop
            if ok
              yield obj
            else
              break
            end
          end
        else
          enum_for(:each)
        end
      end

      def self.new(max = 0)
        max = max.to_i
        if max <= 0
          NonBufferChan.new
        else
          BufferChan.new(max)
        end
      end

      def self.after(seconds)
        ch = new
        CoRun::Routine.new(new_thread: true, queue_tag: :none) do
          sleep seconds
          ch << Time.now rescue nil
          ch.close
        end
        ch
      end

      def self.tick(every_seconds)
        ch = new
        CoRun::Routine.new(new_thread: true, queue_tag: :none) do
          loop do
            sleep every_seconds
            begin
              ch.enq(Time.now, true)
            rescue ThreadError
            end
          end
        end
        ch
      end

      def self.perform(timeout: nil, &blk)
        ch = new
        CoRun::Routine.new(new_thread: false, queue_tag: :default) do
          begin
            Timeout::timeout(timeout) do
              blk.call
            end
          rescue Timeout::Error
          ensure
            ch.close
          end
        end
        ch
      end

      private

      attr_accessor :ios
      attr_accessor :register_mutex

      def register(io)
        register_mutex.synchronize do
          ios.delete_if { |io| io.closed? }
          ios << io
        end
      end

      def notify
        register_mutex.synchronize do
          ios.each do |io|
            io.close rescue nil
          end
          ios.clear
        end
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

        self.ios            = []
        self.register_mutex = Mutex.new
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

                  begin
                    Thread.new do
                      deq_mutex.synchronize do
                        # no op
                      end
                      notify
                    end
                  rescue Exception => ex
                    Rbgo.logger&.error('Rbgo') { "#{ex.message}\n#{ex.backtrace}" }
                    sleep 1
                    retry
                  end

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
        ok       = true
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
            notify
            enq_cond.wait(deq_mutex)
          end
          resource = resource_array.first
          ok       = false if resource_array.empty?
          resource_array.clear
          self.have_deq_waiting_flag = false
          deq_cond.signal
        ensure
          deq_mutex.unlock
        end

        [resource, ok]
      end

      def close
        deq_mutex.synchronize do
          self.close_flag = true
          enq_cond.broadcast
          deq_cond.broadcast
          notify
          self
        end
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
      alias_method :queue_max, :max
      alias_method :queue_max=, :max=
      include Chan
      
      def initialize(max)
        super(max)
        @mutex              = Mutex.new
        @cond               = ConditionVariable.new
        self.ios            = []
        self.register_mutex = Mutex.new
      end

      def push(obj, nonblock = false)
        @mutex.synchronize do
          begin
            if nonblock
              super(obj, true)
            else
              while length == queue_max && !closed?
                @cond.wait(@mutex)
              end
              super(obj, false)
            end
            notify
            @cond.broadcast
            self
          rescue ThreadError
            raise ClosedQueueError.new if closed?
            raise
          end
        end
      end

      def pop(nonblock = false)
        @mutex.synchronize do
          res = nil
          ok  = true
          ok  = false if empty? && closed?
          begin
            if nonblock
              res = super(true)
            else
              while empty? && !closed?
                @cond.wait(@mutex)
              end
              ok  = false if closed?
              res = super(false)
            end
            notify
            @cond.broadcast
          rescue ThreadError
            raise unless closed?
            ok = false
          end
          [res, ok]
        end
      end

      def clear
        super
        notify
        self
      end

      def close
        @mutex.synchronize do
          super
          notify
          @cond.broadcast
          self
        end
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

      io_hash      = {}
      close_io_blk = proc do
        io_hash.each_pair.flat_map do |k, v|
          [k, v[1]]
        end.each do |io|
          io.close rescue nil
        end
      end

      begin
        while true do

          close_io_blk.call
          io_hash.clear

          ops.each do |op|
            io_r, io_w = IO.pipe
            op.register(io_w)
            io_hash[io_r] = [op, io_w]
          end

          ops.each do |op|
            begin
              return op.call
            rescue ThreadError
            end
          end

          return yield if block_given?

          read_ios = IO.select(io_hash.keys).first rescue []

          read_ios.each do |io_r|
            op = io_hash[io_r].first
            begin
              return op.call
            rescue ThreadError
            end
          end
        end
      ensure
        close_io_blk.call
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
      op.define_singleton_method(:register) do |io_w|
        chan.send :register, io_w
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
      op.define_singleton_method(:register) do |io_w|
        chan.send :register, io_w
      end
      op
    end

    module_function :select_chan, :on_read, :on_write
  end
end