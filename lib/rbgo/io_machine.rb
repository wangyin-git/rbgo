require 'nio'
require_relative 'actor'

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

    def do_read_line(io, sep: $/, limit: nil)
      op      = [:register_read_line, io, sep, limit]
      receipt = IOReceipt.new(op)
      actor.send_msg(receipt)
      receipt
    end

    def do_read_partial(io, maxlen:)
      op      = [:register_read_partial, io, maxlen]
      receipt = IOReceipt.new(op)
      actor.send_msg(receipt)
      receipt
    end

    def do_socket_accept(sock)
      op      = [:register_socket_accept, sock]
      receipt = IOReceipt.new(op)
      actor.send_msg(receipt)
      receipt
    end

    def do_socket_connect(sock, remote_sockaddr:)
      op      = [:register_socket_connect, sock, remote_sockaddr]
      receipt = IOReceipt.new(op)
      actor.send_msg(receipt)
      receipt
    end

    def do_socket_recv(sock, maxlen:, flags: 0)
      op      = [:register_socket_recv, sock, maxlen, flags]
      receipt = IOReceipt.new(op)
      actor.send_msg(receipt)
      receipt
    end

    def do_socket_recvmsg(sock, maxdatalen: nil, flags: 0, maxcontrollen: nil, opts: {})
      op      = [:register_socket_recvmsg, sock, maxdatalen, flags, maxcontrollen, opts]
      receipt = IOReceipt.new(op)
      actor.send_msg(receipt)
      receipt
    end

    def do_socket_sendmsg(sock, mesg, flags: 0, dest_sockaddr: nil, controls: [])
      op      = [:register_socket_sendmsg, sock, mesg, flags, dest_sockaddr, controls]
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
          handle_select_msg(actor)
          next
        end

        receipt = msg
        op      = receipt.registered_op

        case op[0]
        when :register_read
          handle_read_msg(receipt, actor)
        when :register_read_line
          handle_read_line_msg(receipt, actor)
        when :register_read_partial
          handle_read_partial_msg(receipt, actor)
        when :register_write
          handle_write_msg(receipt, actor)
        when :register_socket_accept
          handle_socket_accept_msg(receipt, actor)
        when :register_socket_connect
          handle_socket_connect_msg(receipt, actor)
        when :register_socket_recv
          handle_socket_recv_msg(receipt, actor)
        when :register_socket_sendmsg
          handle_socket_sendmsg_msg(receipt, actor)
        when :register_socket_recvmsg
          handle_socket_recvmsg_msg(receipt, actor)
        end
      end #end of actor

    end

    #end of initialize


    def handle_select_msg(actor)
      return if selector.empty?
      selector.select(0.1) do |monitor|
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

    def handle_socket_recv_msg(receipt, actor)
      op     = receipt.registered_op
      io     = op[1]
      maxlen = op[2]
      flags  = op[3]
      res    = ""

      monitor = register(receipt, interest: :r)
      return if monitor.nil?

      monitor.value    ||= []
      monitor.value[0] = proc do
        notify_blk = proc do
          monitors.delete(monitor.io)
          monitor.close
          receipt.res = res
          receipt.notify
        end
        catch :exit do
          begin
            buf = io.recv_nonblock(maxlen, flags, exception: false)
          rescue Exception => ex
            notify_blk.call
            STDERR.puts(ex.backtrace)
            throw :exit
          end
          if buf == :wait_readable
            throw :exit
          elsif buf.nil?
            notify_blk.call
            throw :exit
          end
          res << buf
          notify_blk.call
        end
      end
      actor.send_msg :do_select
    end

    def handle_socket_recvmsg_msg(receipt, actor)
      op              = receipt.registered_op
      sock            = op[1]
      len             = op[2]
      flags           = op[3]
      maxcontrollen   = op[4]
      opts            = op[5]

      data            = ""
      sender_addrinfo = nil
      rflags          = 0
      controls        = []

      monitor = register(receipt, interest: :r)
      return if monitor.nil?
      notify_blk       = proc do
        monitors.delete(monitor.io)
        monitor.close
        if len && len > 0 && data.length == 0
          receipt.res = nil
        else
          receipt.res = [data, sender_addrinfo, rflags, *controls]
        end
        receipt.notify
      end
      monitor.value    ||= []
      monitor.value[0] = proc do
        if len.nil?
          loop do
            begin
              buf = sock.recvmsg_nonblock(nil, flags, maxcontrollen, opts.merge(exception: false))
            rescue Exception => ex
              notify_blk.call
              STDERR.puts(ex.backtrace)
              break
            end
            if buf == :wait_readable
              break
            elsif buf.nil?
              notify_blk.call
              break
            end
            data << buf[0]
            sender_addrinfo = buf[1]
            rflags          = buf[2]
            controls.append(*buf[3..-1])
          end
        elsif len == 0
          notify_blk.call
          break
        else
          bytes_read_n = 0
          loop do
            need_read_bytes_n = len - bytes_read_n
            if need_read_bytes_n <= 0
              notify_blk.call
              break
            end
            begin
              buf = sock.recvmsg_nonblock(need_read_bytes_n, flags, maxcontrollen, opts.merge(exception: false))
            rescue Exception => ex
              notify_blk.call
              STDERR.puts(ex.backtrace)
              break
            end
            if buf == :wait_readable
              break
            elsif buf.nil?
              notify_blk.call
              break
            end
            data << buf[0]
            sender_addrinfo = buf[1]
            rflags          = buf[2]
            controls.append(*buf[3..-1])
            bytes_read_n += buf[0].bytesize
          end
        end
      end
      actor.send_msg :do_select
    end

    def handle_socket_sendmsg_msg(receipt, actor)
      op            = receipt.registered_op
      sock          = op[1]
      str           = op[2].to_s
      flags         = op[3]
      dest_sockaddr = op[4]
      controls      = op[5]
      monitor       = register(receipt, interest: :w)
      return if monitor.nil?

      bytes_written_n  = 0
      monitor.value    ||= []
      monitor.value[1] = proc do
        loop do
          begin
            bytes_need_to_write_n = str.size - bytes_written_n
            if bytes_need_to_write_n > 0
              n = sock.sendmsg_nonblock(str[bytes_written_n..-1], flags, dest_sockaddr, *controls, exception: false)
            else
              monitors.delete(monitor.io)
              monitor.close
              receipt.res = str.bytesize
              receipt.notify
              break
            end
          rescue Exception => ex
            monitors.delete(monitor.io)
            monitor.close
            receipt.res = bytes_written_n
            receipt.notify
            STDERR.puts(ex.backtrace)
            break
          end
          if n == :wait_writable
            break
          end
          bytes_written_n += n
        end
      end
      monitor.value[1].call
      actor.send_msg :do_select
    end

    def handle_socket_connect_msg(receipt, actor)
      op              = receipt.registered_op
      sock            = op[1]
      remote_sockaddr = op[2]
      res             = nil

      monitor = register(receipt, interest: :w)
      return if monitor.nil?

      monitor.value    ||= []
      monitor.value[1] = proc do
        notify_blk = proc do
          monitors.delete(monitor.io)
          monitor.close
          receipt.res = res
          receipt.notify
        end
        catch :exit do
          begin
            res = sock.connect_nonblock(remote_sockaddr, exception: false)
          rescue Exception => ex
            notify_blk.call
            STDERR.puts(ex.backtrace)
            throw :exit
          end
          if res == :wait_writable
            throw :exit
          end
          notify_blk.call
        end
      end
      monitor.value[1].call
      actor.send_msg :do_select
    end

    def handle_socket_accept_msg(receipt, actor)
      op   = receipt.registered_op
      sock = op[1]
      res  = nil

      monitor = register(receipt, interest: :r)
      return if monitor.nil?

      monitor.value    ||= []
      monitor.value[0] = proc do
        notify_blk = proc do
          monitors.delete(monitor.io)
          monitor.close
          receipt.res = res
          receipt.notify
        end
        catch :exit do
          begin
            res = sock.accept_nonblock(exception: false)
          rescue Exception => ex
            notify_blk.call
            STDERR.puts(ex.backtrace)
            throw :exit
          end
          if res == :wait_readable
            throw :exit
          end
          notify_blk.call
        end
      end
      actor.send_msg :do_select
    end

    def handle_read_partial_msg(receipt, actor)
      op     = receipt.registered_op
      io     = op[1]
      maxlen = op[2]
      res    = ""

      monitor = register(receipt, interest: :r)
      return if monitor.nil?

      monitor.value    ||= []
      monitor.value[0] = proc do
        notify_blk = proc do
          monitors.delete(monitor.io)
          monitor.close
          receipt.res = res
          receipt.notify
        end
        catch :exit do
          begin
            buf = io.read_nonblock(maxlen, exception: false)
          rescue Exception => ex
            notify_blk.call
            STDERR.puts(ex.backtrace)
            throw :exit
          end
          if buf == :wait_readable
            throw :exit
          elsif buf.nil?
            notify_blk.call
            throw :exit
          end
          res << buf
          notify_blk.call
        end
      end
      actor.send_msg :do_select
    end

    def handle_read_line_msg(receipt, actor)
      op       = receipt.registered_op
      io       = op[1]
      sep      = op[2]
      limit    = op[3]
      buf_size = 512 * 1024
      res      = ""

      monitor = register(receipt, interest: :r)
      return if monitor.nil?

      monitor.value    ||= []
      monitor.value[0] = proc do
        notify_blk = proc do
          monitors.delete(monitor.io)
          monitor.close
          if limit && limit > 0 && res.length == 0
            receipt.res = nil
          else
            receipt.res = res
          end
          receipt.notify
        end

        sep        = "\n\n" if (sep && sep.length == 0)

        if limit.nil?
          buf_size = 1 unless sep.nil? || io.is_a?(BasicSocket)
          loop do
            begin
              if sep && io.is_a?(BasicSocket)
                buf = io.recv_nonblock(buf_size, Socket::MSG_PEEK, exception: false)
                if buf != :wait_readable && buf.size == 0
                  buf = nil
                end
              else
                buf = io.read_nonblock(buf_size, exception: false)
              end
            rescue Exception => ex
              notify_blk.call
              STDERR.puts(ex.backtrace)
              break
            end
            if buf == :wait_readable
              break
            elsif buf.nil?
              notify_blk.call
              break
            end
            if sep && io.is_a?(BasicSocket)
              sep_index = buf.index(sep)
              if sep_index
                buf = buf[0...sep_index + sep.length]
              end
              res << buf
              io.recv(buf.size)
            else
              res << buf
            end
            unless sep.nil?
              if res.end_with?(sep)
                notify_blk.call
                break
              end
            end
          end
        elsif limit > 0
          bytes_read_n = 0
          loop do
            need_read_bytes_n = limit - bytes_read_n
            if need_read_bytes_n <= 0
              notify_blk.call
              break
            end
            if sep.nil? || io.is_a?(BasicSocket)
              buf_size = need_read_bytes_n
            else
              buf_size = 1
            end
            begin
              if sep && io.is_a?(BasicSocket)
                buf = io.recv_nonblock(buf_size, Socket::MSG_PEEK, exception: false)
                if buf != :wait_readable && buf.size == 0
                  buf = nil
                end
              else
                buf = io.read_nonblock(buf_size, exception: false)
              end
            rescue Exception => ex
              notify_blk.call
              STDERR.puts(ex.backtrace)
              break
            end
            if buf == :wait_readable
              break
            elsif buf.nil?
              notify_blk.call
              break
            end
            if sep && io.is_a?(BasicSocket)
              sep_index = buf.index(sep)
              if sep_index
                buf = buf[0...sep_index + sep.length]
              end
              res << buf
              io.recv(buf.size)
            else
              res << buf
            end
            bytes_read_n += buf.bytesize
            unless sep.nil?
              if res.end_with?(sep)
                notify_blk.call
                break
              end
            end
          end
        else
          notify_blk.call
        end
      end
      actor.send_msg :do_select
    end

    def handle_read_msg(receipt, actor)
      op       = receipt.registered_op
      io       = op[1]
      len      = op[2]
      res      = ""
      buf_size = 1024 * 512

      monitor = register(receipt, interest: :r)
      return if monitor.nil?
      notify_blk       = proc do
        monitors.delete(monitor.io)
        monitor.close
        if len && len > 0 && res.length == 0
          receipt.res = nil
        else
          receipt.res = res
        end
        receipt.notify
      end
      monitor.value    ||= []
      monitor.value[0] = proc do
        if len.nil?
          loop do
            begin
              buf = io.read_nonblock(buf_size, exception: false)
            rescue Exception => ex
              notify_blk.call
              STDERR.puts(ex.backtrace)
              break
            end
            if buf == :wait_readable
              break
            elsif buf.nil?
              notify_blk.call
              break
            end
            res << buf
          end
        elsif len == 0
          notify_blk.call
          break
        else
          bytes_read_n = 0
          loop do
            need_read_bytes_n = len - bytes_read_n
            if need_read_bytes_n <= 0
              notify_blk.call
              break
            end
            begin
              buf = io.read_nonblock(need_read_bytes_n, exception: false)
            rescue Exception => ex
              notify_blk.call
              STDERR.puts(ex.backtrace)
              break
            end
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

    def handle_write_msg(receipt, actor)
      op  = receipt.registered_op
      io  = op[1]
      str = op[2].to_s

      monitor = register(receipt, interest: :w)
      return if monitor.nil?

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
          STDERR.puts(ex.backtrace)
        end
      end
      monitor.value[1].call
      actor.send_msg :do_select
    end

    def register(receipt, interest:)
      io                 = receipt.registered_op[1]
      registered_monitor = monitors[io]
      if registered_monitor && (registered_monitor.interests == interest || registered_monitor.interests == :rw)
        actor.send_msg receipt
        return nil
      end

      if registered_monitor
        registered_monitor.add_interest(interest)
        monitor = registered_monitor
      else
        monitor      = selector.register(io, interest)
        monitors[io] = monitor
      end
      monitor
    end
  end
end