# frozen_string_literal: true

module HTTPX
  module Plugins
    module Compression
      module Brotli 

        def self.load_dependencies(klass, *)
          klass.plugin(:compression)
          require "brotli"
        end

        def self.configure(*)
          Compression.register "br", self 
        end

        module Encoder
          module_function

          def deflate(raw, buffer, chunk_size: )
            begin
              while chunk = raw.read(chunk_size)
                compressed = ::Brotli.deflate(chunk)
                buffer << compressed
                yield compressed if block_given?
              end
            end
          end
        end

        module BrotliWrapper
          module_function
          def inflate(text)
            ::Brotli.inflate(text)
          end
          def close
          end
          def finish
            ""
          end
        end

        module_function
        
        def encoder
          Encoder
        end
        
        def decoder 
          Decoder.new(BrotliWrapper)
        end
      end
    end
    register_plugin :"compression/brotli", Compression::Brotli
  end
end
