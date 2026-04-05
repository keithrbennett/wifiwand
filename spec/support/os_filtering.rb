# frozen_string_literal: true

require_relative '../../lib/wifi-wand/operating_systems'

module OSFiltering
  DISRUPTIVE_OS_TAGS = {
    disruptive_mac:    :os_mac,
    disruptive_ubuntu: :os_ubuntu
  }.freeze

  def self.setup_os_detection(config)
    begin
      current_os = WifiWand::OperatingSystems.current_os
      $compatible_os_tag = "os_#{current_os.id}".to_sym
      $compatible_disruptive_tag = DISRUPTIVE_OS_TAGS.key($compatible_os_tag)
      $incompatible_disruptive_tags = (DISRUPTIVE_OS_TAGS.keys - [$compatible_disruptive_tag]).freeze
    rescue => e
      puts "Warning: Could not detect current OS for test filtering: #{e.message}"
      puts 'Running all tests - some may fail due to OS incompatibility'
    end
  end

  def self.configure_os_filtering(config)
    config.before(:each) do |example|
      skipped_tag = $incompatible_disruptive_tags.find { |t| example.metadata[t] }
      if skipped_tag
        skip "Skipping [:#{skipped_tag}] tests on current OS (#{$compatible_os_tag})"
      end
    end
  end
end
