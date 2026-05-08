# frozen_string_literal: true

require_relative '../../lib/wifi_wand/operating_systems'

module OSFiltering
  class << self
    attr_accessor :compatible_os_tag
  end

  def self.setup_os_detection(_config)
    current_os = WifiWand::OperatingSystems.current_os
    self.compatible_os_tag = :"os_#{current_os.id}"
  rescue => e
    RSpec.configuration.reporter.message(
      "Warning: Could not detect current OS for test filtering: #{e.message}"
    )
    RSpec.configuration.reporter.message('Running all tests - some may fail due to OS incompatibility')
  end

  def self.configure_os_filtering(config)
    config.before do |example|
      next unless example.metadata[:real_env]

      required_os = example.metadata[:real_env_os]
      current_os_tag = OSFiltering.compatible_os_tag
      next unless required_os && current_os_tag && required_os != current_os_tag

      skip "Skipping [:real_env] test for #{required_os} on current OS (#{current_os_tag})"
    end
  end
end
