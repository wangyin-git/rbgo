require 'socket'
require 'openssl'
require_relative 'select_chan'
require_relative 'corun'

module Rbgo
  module NetworkServiceFactory
    using CoRunExtensions
    include Channel

    class Service
      attr_reader :host, :port, :type
      attr_accessor :task

      def alive?
        return service_routine.alive? unless service_routine.nil?
        false
      end

      def stop
        sockets.each do |sock|
          sock.close
        end
      end

      private

      attr_accessor :service_routine, :sockets
      attr_writer :host, :port, :type

      def initialize
        self.type    = :unknown
        self.host    = nil
        self.port    = 0
        self.sockets = []
      end

      class << self
        private :new
      end
    end

    def self.open_tcp_service_with_sockets(sockets, &blk)
      res_chan = Chan.new(1)
      service  = Service.send :new

      routine = go! do
        service.send :type=, :tcp
        service.send :host=, sockets.first.local_address.ip_address
        service.send :port=, sockets.first.local_address.ip_port
        service.task = blk
        service.send :sockets=, sockets
        res_chan << service
        begin
          Socket.accept_loop(sockets) do |sock, clientAddrInfo|
            go do
              if service.task.nil?
                sock.close
              else
                service.task.call(sock, clientAddrInfo)
              end
            end
          end
        rescue Exception => ex
          Rbgo.logger&.error('Rbgo') { "#{ex.message}\n#{ex.backtrace}" }
        end
      end
      service.send :service_routine=, routine
      res_chan.deq
      service
    end

    def self.open_ssl_service(host = nil, port, cert_file, key_file, &blk)
      res_chan = Chan.new(1)
      service  = Service.send :new

      routine = go! do
        service.send :type=, :tcp
        service.send :host=, host
        service.send :port=, port
        service.task = blk
        begin
          cert     = OpenSSL::X509::Certificate.new(File.read(cert_file))
          key      = OpenSSL::PKey::RSA.new(File.open(key_file))
          ctx      = OpenSSL::SSL::SSLContext.new()
          ctx.cert = cert
          ctx.key  = key

          tcp_server = TCPServer.new(host, port)
          service.send :port=, tcp_server.local_address.ip_port
          ssl_server = OpenSSL::SSL::SSLServer.new(tcp_server, ctx)
          service.send :sockets=, [ssl_server]
          res_chan << service
          begin
            loop do
              sock = ssl_server.accept
              sock.sync_close = true
              go do
                if service.task.nil?
                  sock.close
                else
                  service.task.call(sock, sock.io.remote_address)
                end
              end
            end
          rescue Exception => ex
            if ex.is_a? OpenSSL::SSL::SSLError
              Rbgo.logger&.info('Rbgo') { "#{ex.message}\n#{ex.backtrace}" }
              retry
            else
              Rbgo.logger&.error('Rbgo') { "#{ex.message}\n#{ex.backtrace}" }
            end
          end
        rescue Exception => ex
          res_chan << service
          Rbgo.logger&.error('Rbgo') { "#{ex.message}\n#{ex.backtrace}" }
        end
      end
      service.send :service_routine=, routine
      res_chan.deq
      service
    end

    def self.open_tcp_service(host = nil, port, &blk)

      res_chan = Chan.new(1)
      service  = Service.send :new

      routine = go! do
        service.send :type=, :tcp
        service.send :host=, host
        service.send :port=, port
        service.task = blk
        begin
          Socket.tcp_server_sockets(host, port) do |sockets|
            service.send :port=, sockets.first.local_address.ip_port
            service.send :sockets=, sockets
            res_chan << service
            begin
              Socket.accept_loop(sockets) do |sock, clientAddrInfo|
                go do
                  if service.task.nil?
                    sock.close
                  else
                    service.task.call(sock, clientAddrInfo)
                  end
                end
              end
            rescue Exception => ex
              Rbgo.logger&.error('Rbgo') { "#{ex.message}\n#{ex.backtrace}" }
            end
          end
        rescue Exception => ex
          res_chan << service
          Rbgo.logger&.error('Rbgo') { "#{ex.message}\n#{ex.backtrace}" }
        end
      end
      service.send :service_routine=, routine
      res_chan.deq
      service
    end

    def self.open_udp_service_with_sockets(sockets, &blk)
      res_chan = Chan.new(1)
      service  = Service.send :new
      routine  = go! do
        service.send :type=, :udp
        service.send :host=, sockets.first.local_address.ip_address
        service.send :port=, sockets.first.local_address.ip_port
        service.task = blk
        service.send :sockets=, sockets
        res_chan << service
        begin
          Socket.udp_server_loop_on(sockets) do |msg, msg_src|
            go do
              service.task.call(msg, msg_src) unless service.task.nil?
            end
          end
        rescue Exception => ex
          Rbgo.logger&.error('Rbgo') { "#{ex.message}\n#{ex.backtrace}" }
        end
      end
      service.send :service_routine=, routine
      res_chan.deq
      service
    end

    def self.open_udp_service(host = nil, port, &blk)

      res_chan = Chan.new(1)
      service  = Service.send :new

      routine = go! do
        service.send :type=, :udp
        service.send :host=, host
        service.send :port=, port
        service.task = blk
        begin
          Socket.udp_server_sockets(host, port) do |sockets|
            service.send :port=, sockets.first.local_address.ip_port
            service.send :sockets=, sockets
            res_chan << service
            begin
              Socket.udp_server_loop_on(sockets) do |msg, msg_src|
                go do
                  service.task.call(msg, msg_src) unless service.task.nil?
                end
              end
            rescue Exception => ex
              Rbgo.logger&.error('Rbgo') { "#{ex.message}\n#{ex.backtrace}" }
            end
          end
        rescue Exception => ex
          res_chan << service
          Rbgo.logger&.error('Rbgo') { "#{ex.message}\n#{ex.backtrace}" }
        end
      end
      service.send :service_routine=, routine
      res_chan.deq
      service
    end
  end
end