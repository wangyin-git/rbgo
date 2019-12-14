require 'thread'
require_relative 'synchronized_collection'
require_relative 'corun'

module Rbgo
  module Observable
    @mutex = Mutex.new

    def add_observer(observer, func = :update)
      unless defined? @observer_peers
        Observable.instance_variable_get(:@mutex).synchronize do
          @observer_peers = SyncHash.new unless defined? @observer_peers
        end
      end

      unless observer.respond_to? func
        raise NoMethodError, "observer does not respond to `#{func}'"
      end
      @observer_peers[observer] = func
    end

    def delete_observer(observer)
      @observer_peers.delete observer if defined? @observer_peers
    end

    def delete_observers
      @observer_peers.clear if defined? @observer_peers
    end

    def count_observers
      if defined? @observer_peers
        @observer_peers.size
      else
        0
      end
    end

    def changed(state = true)
      Observable.instance_variable_get(:@mutex).synchronize do
        @observer_state = state
      end
    end

    def changed?
      if defined? @observer_state and @observer_state
        true
      else
        false
      end
    end

    def notify_observers(*arg)
      if defined? @observer_state and @observer_state
        if defined? @observer_peers
          Observable.instance_variable_get(:@mutex).synchronize do
            if @observer_state
              @observer_peers.each do |k, v|
                CoRun::Routine.new(new_thread: false, queue_tag: :default) do
                  k.send v, *arg
                end
              end
              @observer_state = false
            end
          end
        end
      end
    end
  end
end
