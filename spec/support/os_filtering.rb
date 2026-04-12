# frozen_string_literal: true

require_relative '../../lib/wifi-wand/operating_systems'

module OSFiltering
  def self.setup_os_detection(_config)
    current_os = WifiWand::OperatingSystems.current_os
    $compatible_os_tag = :"os_#{current_os.id}"
  rescue => e
    puts "Warning: Could not detect current OS for test filtering: #{e.message}"
    puts 'Running all tests - some may fail due to OS incompatibility'
  end

  def self.configure_os_filtering(config)
    config.before do |example|
      next unless example.metadata[:real_env]

      required_os = example.metadata[:real_env_os]
      next unless required_os && defined?($compatible_os_tag) && required_os != $compatible_os_tag

      skip "Skipping [:real_env] test for #{required_os} on current OS (#{$compatible_os_tag})"
    end
  end
end
