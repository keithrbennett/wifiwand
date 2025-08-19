require 'awesome_print'

module WifiWand
  class CommandLineInterface
    module OutputFormatter
      
      def fancy_string(object)
        object.awesome_inspect
      end

      def fancy_puts(object)
        puts fancy_string(object)
      end
      alias_method :fp, :fancy_puts

      # If a post-processor has been configured (e.g. YAML or JSON), use it.
      def post_process(object)
        post_processor ? post_processor.(object) : object
      end

      def post_processor
        options.post_processor
      end
      
    end
  end
end