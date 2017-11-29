# frozen_string_literal: true

require "forwardable"
require "openssl"

module HTTPX::Channel
  class SSL < TCP
    def protocol
      @io.alpn_protocol
    end

    if OpenSSL::VERSION < "2.0.6"
      # OpenSSL < 2.0.6 has a leak in the buffer destination data.
      # It has been fixed as of 2.0.6: https://github.com/ruby/openssl/pull/153
      def dread(size = BUFFER_SIZE)
        begin
          loop do
            @io.read_nonblock(size, @read_buffer)
            @processor << @read_buffer
          end
        rescue IO::WaitReadable
          return 
        rescue EOFError
          # EOF
          throw(:close, self)
        end
      end
    end

    private

    def connect
      ssl = @options.ssl
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params(ssl)
      ctx.alpn_protocols = %w[h2 http/1.1] if ctx.respond_to?(:alpn_protocols=)
      ctx.alpn_select_cb = lambda do |pr|
        pr.first unless pr.nil? || pr.empty? 
      end if ctx.respond_to?(:alpn_select_cb=) 

      super
      @io = OpenSSL::SSL::SSLSocket.new(@io, ctx)
      @io.hostname = uri.host
      @io.sync_close = true
      @io.connect # TODO: non-block variant missing
    end

    def perform_io
      yield
    rescue IO::WaitReadable, IO::WaitWritable
    # wait read/write
    rescue EOFError
      # EOF
      @io.close
    end

  end
end
