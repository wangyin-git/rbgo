require 'thread'
require_relative 'once'

module Rbgo
  class Actor
    private

    attr_accessor :mail_box, :once_for_msg_loop

    public

    attr_accessor :handler

    def initialize(&handler)
      self.handler           = handler
      self.mail_box          = Queue.new
      self.once_for_msg_loop = Once.new
    end

    def send_msg(msg)
      mail_box << msg
      start_msg_loop
      nil
    end

    def close
      mail_box.close
      mail_box.clear
      nil
    end

    def closed?
      mail_box.closed?
    end

    private

    def start_msg_loop
      once_for_msg_loop.do do
        CoRun::Routine.new(new_thread: false, queue_tag: :default) do
          loop do
            begin
              msg = mail_box.deq(true)
            rescue ThreadError
              self.once_for_msg_loop = Once.new
              if mail_box.empty?
                break
              else
                start_msg_loop
              end
            else
              call_handler(msg)
            end
            Fiber.yield
          end
        end
      end
    end

    def call_handler(msg)
      handler.call(msg, self) if handler
    rescue Exception => ex
      STDERR.puts ex
    end
  end
end