require 'thread'

module Rbgo
  class Actor
    private

    attr_accessor :mail_box, :msg_loop_thread

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
      self.msg_loop_thread = Thread.new do
        while msg = mail_box.deq
          handler.call(msg) rescue nil
        end
      end
    end
  end
end