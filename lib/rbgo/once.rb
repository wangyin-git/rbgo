require 'thread'

module Rbgo
  class Once

    def initialize
      self.mutex       = Mutex.new
      self.called_flag = false
    end

    def do(&f)
      return nil if called_flag
      mutex.synchronize do
        unless called_flag
          begin
            f.call
          ensure
            self.called_flag = true
          end
        end
      end
    end

    private

    attr_accessor :mutex, :called_flag
  end
end