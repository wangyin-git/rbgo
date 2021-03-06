require_relative 'rbgo/corun'
require_relative 'rbgo/select_chan'
require_relative 'rbgo/wait_group'
require_relative 'rbgo/reentrant_mutex'
require_relative 'rbgo/reentrant_rw_mutex'
require_relative 'rbgo/semaphore'
require_relative 'rbgo/synchronized_collection'
require_relative 'rbgo/observer'
require_relative 'rbgo/once'
require_relative 'rbgo/actor'
require_relative 'rbgo/task_list'
require_relative 'rbgo/io_machine'
require_relative 'rbgo/network_service'
require_relative 'rbgo/version'
require 'logger'

module Rbgo
  class << self
    attr_accessor :logger
  end
  self.logger = Logger.new(STDERR, level: Logger::DEBUG)
end