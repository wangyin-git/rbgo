require 'thread'
require 'set'

module Rbgo
  class Actor
    private

    attr_accessor :mail_box

    public

    attr_accessor :handler

    def initialize(&handler)
      self.handler  = handler
      self.mail_box = Queue.new
      start_msg_loop
    end

    def send_msg(msg)
      mail_box << msg
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
      CoRun::Routine.new(new_thread: true, queue_tag: :default) do
        loop do
          begin
            msg = mail_box.deq(true)
          rescue ThreadError
            unless CoRun.have_other_task_on_thread?
              msg = mail_box.deq
              break if mail_box.closed?
              call_handler(msg)
            end
          else
            call_handler(msg)
          end
          Fiber.yield
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