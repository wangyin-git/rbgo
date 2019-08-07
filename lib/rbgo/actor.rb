require 'thread'
require_relative 'corun'

using Rbgo::CoRunExtensions

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
      go! do
        while msg = mail_box.deq
          handler.call(msg, self) rescue nil
        end
      end
    end
  end
end