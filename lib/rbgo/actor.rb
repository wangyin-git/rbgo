require 'thread'


module Rbgo
  class Actor
    private

    ACTOR_QUEUE_TAG = :actor_bbc0f70e
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
          break if mail_box.closed?
          msg = mail_box.deq
          handler.call(msg, self) rescue nil
          Fiber.yield
        end
      end
    end
  end
end