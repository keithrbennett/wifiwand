# frozen_string_literal: true

require_relative '../../lib/wifi-wand/operating_systems'

module OSFiltering
  def self.setup_os_detection(config)
    # Auto-detect current OS and filter tests accordingly
    begin
      current_os = WifiWand::OperatingSystems.current_os
      current_os_id = current_os.id  # This returns :mac or :ubuntu
      compatible_os_tag = "os_#{current_os_id}".to_sym

      # Store in global variable for use in before hooks
      $compatible_os_tag = compatible_os_tag

    rescue => e
      puts "Warning: Could not detect current OS for test filtering: #{e.message}"
      puts 'Running all tests - some may fail due to OS incompatibility'
    end
  end

  def self.configure_os_filtering(config)
    # Skip OS-incompatible tests before they run
    config.before(:each) do |example|
      # Skip OS-incompatible tests
      os_tags = example.metadata.keys.select { |key| key.to_s.start_with?('os_') }
      if os_tags.any? && !os_tags.include?($compatible_os_tag)
        skip "Skipping #{os_tags.inspect} tests on current OS (#{$compatible_os_tag})"
      end
    end
  end
end