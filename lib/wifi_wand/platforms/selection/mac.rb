# frozen_string_literal: true

require 'rbconfig'

require_relative 'base'

module WifiWand
  module Platforms
    module Selection
      class Mac < Base
        def initialize = super(:mac, 'macOS')

        def current_os_is_this_os? = /darwin/.match?(RbConfig::CONFIG['host_os'])

        def create_model(options)
          raise ArgumentError, 'options must be a Hash' unless options.is_a?(Hash)

          require_relative '../mac/model'
          WifiWand::Platforms::Mac::Model.create_model(options)
        end
      end
    end
  end
end
