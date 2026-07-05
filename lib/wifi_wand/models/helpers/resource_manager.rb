# frozen_string_literal: true

require 'yaml'

module WifiWand
  module Models
    module Helpers
      class ResourceManager
        OpenResource = Struct.new(:code, :url, :description) do
          def help_string = "'#{code}' (#{description})"
        end

        class OpenResources < Array
          def find_by_code(code) = detect { |resource| resource.code == code }

          def help_string = map(&:help_string).join(', ')
        end

        def open_resources = @open_resources ||= load_resources

        def invalid_resource_codes(*resource_codes)
          normalized_resource_codes(resource_codes).reject { |code| open_resources.find_by_code(code) }
        end

        # Opens resources by their abbreviation codes
        # @param model [BaseModel] The model instance that will open the resources
        # @param resource_codes [Array<String,Symbol>] Resource codes to open
        # @return [Hash] with :opened_resources and :invalid_codes arrays
        # @raise [ArgumentError] if model is nil
        def open_resources_by_codes(model, *resource_codes)
          raise ArgumentError, 'Model cannot be nil' if model.nil?

          resource_codes = normalized_resource_codes(resource_codes)
          return { opened_resources: [], invalid_codes: [] } if resource_codes.empty?

          invalid_codes = invalid_resource_codes(*resource_codes)
          unless invalid_codes.empty?
            return { opened_resources: [], invalid_codes: invalid_codes }
          end

          opened_resources = resource_codes.map do |code|
            resource = open_resources.find_by_code(code)

            model.open_resource(resource.url)
            resource
          end

          { opened_resources: opened_resources, invalid_codes: invalid_codes }
        end

        # Get help string for available resources
        def available_resources_help
          "Please specify a resource to open:\n #{open_resources.help_string.gsub(',', "\n")}"
        end

        # Get error message for invalid codes
        def invalid_codes_error(invalid_codes)
          codes_string = invalid_codes.map { |code| "'#{code}'" }.join(', ')
          pluralized_codes = invalid_codes.length > 1 ? 'codes' : 'code'
          resource_list_str = open_resources.help_string.gsub(',', "\n")
          "Invalid resource #{pluralized_codes}: #{codes_string}. Valid codes are:\n #{resource_list_str}"
        end

        private def normalized_resource_codes(resource_codes)
          resource_codes.map(&:to_s)
        end

        private def load_resources
          yaml_path = resource_file_path

          unless File.exist?(yaml_path)
            raise Errno::ENOENT, "Resource file not found: #{yaml_path}"
          end

          begin
            data = YAML.safe_load_file(yaml_path)
          rescue Psych::SyntaxError => e
            raise ArgumentError, "Invalid YAML in resource file #{yaml_path}: #{e.message}"
          end

          unless data.is_a?(Hash) && data.key?('resources')
            raise ArgumentError,
              "Resource file #{yaml_path} must contain a 'resources' key with an array of resources"
          end

          resources = data['resources'].map do |resource|
            next if resource.nil? || !resource.is_a?(Hash)

            OpenResource.new(resource['code'], resource['url'], resource['desc'])
          end.compact

          OpenResources.new(resources)
        end

        private def resource_file_path = File.join(File.dirname(__FILE__), '..', '..', 'data',
          'open_resources.yml')
      end
    end
  end
end
