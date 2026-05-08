# frozen_string_literal: true

require_relative 'base_os'

module WifiWand
  class MacOs < BaseOs
    def initialize = super(:mac, 'macOS')

    def current_os_is_this_os? = /darwin/.match?(RbConfig::CONFIG['host_os'])

    def create_model(options)
      raise ArgumentError, 'options must be a Hash' unless options.is_a?(Hash)

      require_relative '../models/mac_os_model'
      MacOsModel.create_model(options)
    end
  end
end
