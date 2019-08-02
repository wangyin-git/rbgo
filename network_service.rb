require 'socket'
require_relative 'select_chan'
require_relative 'corun'

module NetworkServiceFactory
  class Service
    attr_reader :host, :port, :type
    attr_accessor :task

    def alive?
      service_thread.alive?
    end

    def stop
      service_thread.terminate
    end

    private

    attr_accessor :service_thread
    attr_writer :host, :port, :type

    def initialize
      self.type = :unknown
      self.host = nil
      self.port = 0
    end

    class << self
      private :new
    end
  end

  def open_tcp_service(host = nil, port, &blk)

    res_chan = Chan.new(1)

    go do
      service = Service.send :new
      service.send :service_thread=, Thread.current
      service.send :type=, :tcp
      service.send :host=, host
      service.send :port=, port
      service.task = blk
      begin
        Socket.tcp_server_sockets(host, port) do |sockets|
          service.send :port=, sockets.first.local_address.ip_port
          res_chan << service

          begin
            Socket.accept_loop(sockets) do |sock, clientAddrInfo|
              go do
                begin
                  service.task.call(sock, clientAddrInfo) unless service.task.nil?
                ensure
                  sock.close
                end
              end
            end
          rescue Exception => ex
            STDERR.puts ex
          end

        end
      rescue Exception => ex
        res_chan << service
        STDERR.puts ex
      end
    end

    res_chan.deq
  end

  def open_udp_service(host = nil, port, &blk)

    res_chan = Chan.new(1)

    go do
      service = Service.send :new
      service.send :service_thread=, Thread.current
      service.send :type=, :udp
      service.send :host=, host
      service.send :port=, port
      service.task = blk
      begin
        Socket.udp_server_sockets(host, port) do |sockets|
          service.send :port=, sockets.first.local_address.ip_port
          res_chan << service

          begin
            Socket.udp_server_loop_on(sockets) do |msg, msg_src|
              go do
                service.task.call(msg, msg_src) unless service.task.nil?
              end
            end
          rescue Exception => ex
            STDERR.puts ex
          end

        end
      rescue Exception => ex
        res_chan << service
        STDERR.puts ex
      end
    end

    res_chan.deq
  end

  module_function :open_tcp_service, :open_udp_service
  public :open_tcp_service, :open_udp_service
end