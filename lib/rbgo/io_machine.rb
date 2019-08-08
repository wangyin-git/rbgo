require 'nio'
require_relative 'actor'

module Rbgo
  class IOReceipt
    attr_reader :registered_op
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

    attr_accessor :done_flag, :mutex, :cond
    attr_writer :registered_op

    def initialize(op)
      self.done_flag     = false
      self.mutex         = Mutex.new
      self.cond          = ConditionVariable.new
      self.registered_op = op
    end
  end




  class IOMachine
    def do_read(io, length: nil)
      op      = [:register_read, io, length]
      receipt = IOReceipt.new(op)
      actor.send_msg(receipt)
      receipt
    end

    def do_write(io, str:)
      op      = [:register_write, io, str]
      receipt = IOReceipt.new(op)
      actor.send_msg(receipt)
      receipt
    end

    def close
      actor.close
      selector.close
    end

    def closed?
      actor.closed? && selector.closed?
    end

    private

    attr_accessor :selector, :actor, :monitors

    def initialize
      self.selector = NIO::Selector.new
      self.monitors = {}

      self.actor = Actor.new do |msg, actor|
        if msg == :do_select
          handle_select_msg(msg, actor)
          next
        end

        receipt = msg
        op      = receipt.registered_op

        case
        when param_pattern_match([:register_read, IO, Integer], op)
          handle_read_msg(receipt)
        when param_pattern_match([:register_write, IO, String], op)
          handle_write_msg(receipt)
        end
      end #end of actor

    end #end of initialize



    def handle_select_msg(msg, actor)
      return if selector.empty?
      selector.select(1) do |monitor|
        if monitor.readiness == :r
          monitor.value[0].call
        elsif monitor.readiness == :w
          monitor.value[1].call
        else
          monitor.value[0].call
          monitor.value[1].call
        end
      end
      return if selector.empty?
      actor.send_msg :do_select
      nil
    end


    def handle_read_msg(receipt)
      op                 = receipt.registered_op
      io                 = op[1]
      len                = op[2]
      registered_monitor = monitors[io]
      if registered_monitor && (registered_monitor.interests == :r || registered_monitor.interests == :rw)
        actor.send_msg receipt
        return
      end

      if registered_monitor
        registered_monitor.add_interest(:r)
        monitor = registered_monitor
      else
        monitor      = selector.register(io, :r)
        monitors[io] = monitor
      end

      monitor.value    ||= []
      monitor.value[0] = proc do
        res      = StringIO.new
        buf_size = 1024 * 512
        if len.nil?
          loop do
            buf = io.read_nonblock(buf_size, exception: false)
            if buf == :wait_readable
              break
            elsif buf.nil?
              monitors.delete(monitor.io)
              monitor.close
              receipt.res = res.string
              receipt.notify
              break
            end
            res << buf
          end
        elsif len == 0
          monitors.delete(monitor.io)
          monitor.close
          receipt.res = ""
          receipt.notify
          break
        else
          notify_blk = proc do
            monitors.delete(monitor.io)
            monitor.close
            if res.string.length == 0
              receipt.res = nil
            else
              receipt.res = res.string
            end
            receipt.notify
          end

          bytes_read_n = 0
          loop do
            need_read_bytes_n = len - bytes_read_n
            if need_read_bytes_n <= 0
              notify_blk.call
              break
            end
            buf = io.read_nonblock(need_read_bytes_n, exception: false)
            if buf == :wait_readable
              break
            elsif buf.nil?
              notify_blk.call
              break
            end
            res << buf
            bytes_read_n += buf.bytesize
          end
        end
      end
      actor.send_msg :do_select
    end


    def handle_write_msg(receipt)
      op  = receipt.registered_op
      io  = op[1]
      str = op[2].to_s

      registered_monitor = monitors[io]
      if registered_monitor && (registered_monitor.interests == :w || registered_monitor.interests == :rw)
        actor.send_msg receipt
        return
      end

      if registered_monitor
        registered_monitor.add_interest(:w)
        monitor = registered_monitor
      else
        monitor      = selector.register(io, :w)
        monitors[io] = monitor
      end

      buf = NIO::ByteBuffer.new(str.bytesize)
      buf << str
      buf.flip
      bytes_written_n  = 0
      monitor.value    ||= []
      monitor.value[1] = proc do
        begin
          if buf.remaining > 0
            n               = buf.write_to(io)
            bytes_written_n += n
          else
            monitors.delete(monitor.io)
            monitor.close
            receipt.res = str.bytesize
            receipt.notify
          end
        rescue Exception => ex
          monitors.delete(monitor.io)
          monitor.close
          receipt.res = bytes_written_n
          receipt.notify
        end
      end
      actor.send_msg :do_select
    end


    def param_pattern_match(pattern, params)
      return false unless pattern.is_a?(Array) && params.is_a?(Array)
      return false if pattern.size != params.size
      match = true
      pattern.zip(params) do |type, param|
        unless type === param
          match = false
          break
        end
      end
      match
    end
  end
end