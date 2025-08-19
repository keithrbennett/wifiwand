require 'yaml'

module WifiWand
  class CommandLineInterface
    module ResourceManager
      
      class OpenResource < Struct.new(:code, :resource, :description)

        # Ex: "'ipw' (What is My IP)"
        def help_string
          "'#{code}' (#{description})"
        end
      end

      class OpenResources < Array

        def find_by_code(code)
          detect { |resource| resource.code == code }
        end

        # Ex: "('ipc' (IP Chicken), 'ipw' (What is My IP), 'spe' (Speed Test))"
        def help_string
          map(&:help_string).join(', ')
        end
      end

      def open_resources
        @open_resources ||= begin
          yaml_path = File.join(File.dirname(__FILE__), '..', 'data', 'open_resources.yml')
          data = YAML.safe_load_file(yaml_path)
          resources = data['resources'].map do |resource|
            OpenResource.new(resource['code'], resource['url'], resource['desc'])
          end
          OpenResources.new(resources)
        end
      end
    end
  end
end