require 'thread'
require_relative 'once'
require_relative 'synchronized_collection'
require_relative 'reentrant_mutex'

module Rbgo
  class ActorClosedMsg
    attr_accessor :actor

    def initialize(actor)
      self.actor = actor
    end
  end

  class Actor
    private

    attr_accessor :mail_box, :once_for_msg_loop, :once_for_close,
                  :close_mutex, :parent, :children, :linked_actors, :supervisor_actors

    public

    attr_accessor :handler
    attr_reader :close_reason

    def initialize(&handler)
      self.handler           = handler
      @close_reason          = nil
      self.mail_box          = Queue.new
      self.once_for_msg_loop = Once.new
      self.once_for_close    = Once.new
      self.close_mutex       = ReentrantMutex.new

      self.children          = SyncSet.new
      self.linked_actors     = SyncSet.new
      self.supervisor_actors = SyncSet.new
    end

    def send_msg(msg)
      mail_box << msg
      start_msg_loop
      self
    end

    def send_children(msg)
      children.each do |child|
        child.send_msg(msg) rescue nil
      end
      self
    end

    def close(reason = nil)
      once_for_close.do do
        close_mutex.synchronize do
          @close_reason = reason
          mail_box.close
          mail_box.clear

          (parent&.send :children)&.delete(self)
          self.parent   = nil
          self.children = nil

          linked_actors.each do |l|
            CoRun::Routine.new(new_thread: false, queue_tag: :default) do
              l.close
            end
          end
          self.linked_actors = nil

          supervisor_actors.each do |sup|
            sup.send_msg(ActorClosedMsg.new(self)) rescue nil
          end
          self.supervisor_actors = nil

          nil
        end
      end
    end

    def closed?
      mail_box.closed?
    end

    def spawn_child(&handler)
      close_mutex.synchronize do
        raise "can not spawn from a closed actor" if closed?
        child = Actor.new(&handler)
        child.send :parent=, self
        children.add(child)
        child
      end
    end

    def spawn_link(&handler)
      close_mutex.synchronize do
        raise "can not spawn from a closed actor" if closed?
        l = spawn_child(&handler)
        l.send(:linked_actors).add(self)
        linked_actors.add(l)
        l
      end
    end

    def link(actor)
      return self if self.equal?(actor)
      close_mutex.synchronize do
        raise "can not link from a closed actor" if closed?
        actor.send(:close_mutex).synchronize do
          if actor.closed?
            close
          else
            actor.send(:linked_actors).add(self)
            linked_actors.add(actor)
          end
        end
        self
      end
    end

    def unlink(actor)
      return self if self.equal?(actor)
      close_mutex.synchronize do
        raise "can not unlink from a closed actor" if closed?
        actor.send(:close_mutex).synchronize do
          unless actor.closed?
            actor.send(:linked_actors).delete(self)
          end
          linked_actors.delete(actor)
        end
        self
      end
    end

    def spawn_monitor(&handler)
      close_mutex.synchronize do
        raise "can not spawn from a closed actor" if closed?
        m = spawn_child(&handler)
        m.send(:supervisor_actors).add(self)
        m
      end
    end

    def monitor(actor)
      return self if self.equal?(actor)
      close_mutex.synchronize do
        raise "can not monitor from a closed actor" if closed?
        actor.send(:close_mutex).synchronize do
          if actor.closed?
            send_msg(ActorClosedMsg.new(actor))
          else
            actor.send(:supervisor_actors).add(self)
          end
        end
        self
      end
    end

    def demonitor(actor)
      return self if self.equal?(actor)
      close_mutex.synchronize do
        raise "can not demonitor from a closed actor" if closed?
        actor.send(:close_mutex).synchronize do
          actor.send(:supervisor_actors)&.delete(self)
        end
        self
      end
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
              start_msg_loop unless (mail_box.empty? || mail_box.closed?)
              break
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
      close(ex)
      Rbgo.logger&.error('Rbgo') { "#{ex.message}\n#{ex.backtrace}" }
    end
  end
end