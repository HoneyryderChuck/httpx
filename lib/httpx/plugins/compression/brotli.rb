# frozen_string_literal: true

module HTTPX
  module Plugins
    module Compression
      module Brotli 

        def self_load_dependencies(klass, *)
          klass.plugin(:compression)
          require "brotli"
        end

        def self.configure(*)
          Transcoder.register "br", BrotliTranscoder
        end

        module BrotliTranscoder
          module_function
          
          def encode(payload)
            Brotli.encode(payload)
          end
          
          def decode(io)
            Brotli.decode(io)
          end
        end

      end
    end
    register_plugin :"compression/brotli", Compression::Brotli
  end
end
