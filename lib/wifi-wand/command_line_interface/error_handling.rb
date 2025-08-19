module WifiWand
  class CommandLineInterface
    module ErrorHandling
      
      class BadCommandError < RuntimeError
        def initialize(error_message)
          super
        end
      end
    end
  end
end