require 'awesome_print'

module WifiWand
  class CommandLineInterface
    module OutputFormatter
      
      def format_object(object)
        $stdout.tty? ? object.awesome_inspect : object.awesome_inspect(plain: true)
      end


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