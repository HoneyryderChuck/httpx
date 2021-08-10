# frozen_string_literal: true

module HTTPX
  # Adds a general-purpose registry API to a class. It is designed to be a
  # configuration-level API, i.e. the registry is global to the class and
  # should be set on **boot time**.
  #
  # It is used internally to associate tags with handlers.
  #
  # ## Register/Fetch
  #
  # One is strongly advised to register handlers when creating the class.
  #
  # There is an instance-level method to retrieve from the registry based
  # on the tag:
  #
  #     class Server
  #       include HTTPX::Registry
  #
  #       register "tcp", TCPHandler
  #       register "ssl", SSLHandlers
  #       ...
  #
  #
  #       def handle(uri)
  #         scheme = uri.scheme
  #         handler = registry(scheme) #=> TCPHandler
  #         handler.handle
  #       end
  #     end
  #
  module Registry
    # Base Registry Error
    class Error < Error; end

    def self.extended(klass)
      super
      klass.extend(ClassMethods)
    end

    def self.included(klass)
      super
      klass.extend(ClassMethods)
      klass.__send__(:include, InstanceMethods)
    end

    # Class Methods
    module ClassMethods
      def inherited(klass)
        super
        klass.instance_variable_set(:@registry, @registry.dup)
      end

      # @param [Object] tag the handler identifier in the registry
      # @return [Symbol, String, Object] the corresponding handler (if Symbol or String,
      #   will assume it referes to an autoloaded module, and will load-and-return it).
      #
      def registry(tag = nil)
        @registry ||= {}
        return @registry if tag.nil?

        handler = @registry[tag]
        raise(Error, "#{tag} is not registered in #{self}") unless handler

        handler
      end

      # @param [Object] tag the identifier for the handler in the registry
      # @return [Symbol, String, Object] the handler (if Symbol or String, it is
      #   assumed to be an autoloaded module, to be loaded later)
      #
      def register(tag, handler)
        registry[tag] = handler
      end
    end

    # Instance Methods
    module InstanceMethods
      # delegates to HTTPX::Registry#registry
      def registry(tag)
        self.class.registry(tag)
      end
    end
  end
end
