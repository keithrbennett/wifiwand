# frozen_string_literal: true

require 'simplecov'

module CoverageConfig
  def self.setup
    SimpleCov.start do
      add_filter '/spec/'
      add_filter '/vendor/'
      add_filter '/tmp/'
      
      # Group coverage by directory
      add_group "Models", "lib/wifi-wand/models"
      add_group "Services", "lib/wifi-wand/services"
      add_group "OS Detection", "lib/wifi-wand/os"
      add_group "Core", "lib/wifi-wand"
      
      # Set minimum coverage threshold (only enforce if explicitly requested)
      if ENV['COVERAGE_STRICT'] == 'true'
        minimum_coverage 80
        minimum_coverage_by_file 70
      end
      
      # Generate multiple output formats
      formatter SimpleCov::Formatter::MultiFormatter.new([
        SimpleCov::Formatter::HTMLFormatter,
        SimpleCov::Formatter::SimpleFormatter
      ])
      
      # Only track coverage when running the full test suite
      enable_coverage :branch if ENV['COVERAGE_BRANCH'] == 'true'
    end
  end
end