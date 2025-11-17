# frozen_string_literal: true

# =============================================================================
# Output Format End-to-End Tests
# =============================================================================
#
# PURPOSE:
# Tests the complete command-line-to-output flow for all configurable output
# formats. These tests validate that the entire stack works correctly from
# parsing "-o j" on the command line through to formatted output, including
# edge cases, error handling, and real-world usage patterns.
#
# WHAT THIS FILE TESTS:
# - Full command-line argument parsing: "-o j info" → JSON output
# - All 5 formats with multiple commands (info, wifi status, preferred networks)
# - Edge cases and error handling:
#   * Invalid format codes (proper ConfigurationError raised)
#   * Case insensitivity (-o J and -o j both work)
#   * Unicode characters in all formats (日本語, emoji)
#   * Special characters in YAML (colons, spaces, symbols)
#   * Pretty JSON vs compact JSON whitespace differences
# - Multi-command sequences with consistent formatting
# - Type preservation through JSON serialization
# - Output stability and reproducibility (same input → same output)
# - Default behavior without -o flag (human-readable awesome_print)
#
# HOW IT DIFFERS FROM output_formats_integration_spec.rb:
# - END-TO-END focus: Tests complete ARGV parsing → CLI → command → output flow
# - REAL-WORLD scenarios: Unicode, special chars, invalid inputs, case handling
# - ERROR handling: Tests invalid format codes and edge cases
# - COMMAND-LINE integration: Tests actual "-o j" argument parsing via Main class
# - MULTI-COMMAND testing: Verifies format consistency across command sequences
#
# The integration file focuses on systematic data type coverage (strings,
# booleans, arrays, hashes, nil) with parse validation for each format.
# This file tests the complete user experience from command line to output,
# including error cases and complex real-world scenarios.
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/main'
require_relative '../../../lib/wifi-wand/command_line_interface'
require 'json'
require 'yaml'

describe 'Output Format End-to-End Tests' do
  include TestHelpers

  let(:mock_model) { create_standard_mock_model }
  let(:mock_os) { create_mock_os_with_model(mock_model) }

  before do
    allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(mock_os)
    allow_any_instance_of(WifiWand::CommandLineInterface).to receive(:run_shell)
  end

  # Helper method to parse command line arguments
  def parse_options(*args)
    stub_const('ARGV', args.dup)
    main = WifiWand::Main.new
    main.send(:parse_command_line)
  end

  describe 'Command-line option parsing and output formatting' do
    let(:test_network_info) do
      {
        'ssid' => 'TestNetwork',
        'channel' => 6,
        'signal_strength' => -50,
        'security' => 'WPA2',
        'connected' => true
      }
    end

    {
      'i' => { name: 'inspect' },
      'j' => { name: 'JSON' },
      'k' => { name: 'Pretty JSON' },
      'p' => { name: 'puts' },
      'y' => { name: 'YAML' }
    }.each do |format_code, config|
      context "with -o #{format_code} (#{config[:name]}) option" do
        it 'formats wifi info output correctly' do
          allow(mock_model).to receive(:wifi_info).and_return(test_network_info)

          # Parse command line options
          options = parse_options('-o', format_code, 'info')
          expect(options.post_processor).not_to be_nil

          # Create CLI with parsed options
          cli = WifiWand::CommandLineInterface.new(options)

          # Execute command and capture output
          output = silence_output do |stdout, _stderr|
            cli.cmd_i
            stdout.string.strip
          end

          # Validate output format based on format code
          case format_code
          when 'i'
            expect(output).to include('ssid')
          when 'j'
            expect(JSON.parse(output)).to eq(JSON.parse(test_network_info.to_json))
          when 'k'
            parsed = JSON.parse(output)
            expect(parsed).to eq(JSON.parse(test_network_info.to_json))
            expect(output).to match(/\n/)
          when 'p'
            expect(output).to be_a(String)
          when 'y'
            expect(YAML.safe_load(output)).to eq(YAML.safe_load(test_network_info.to_yaml))
          end
        end

        it 'formats boolean output correctly' do
          allow(mock_model).to receive(:connected_to_internet?).and_return(true)

          options = parse_options('-o', format_code, 'ci')
          cli = WifiWand::CommandLineInterface.new(options)

          output = silence_output do |stdout, _stderr|
            cli.cmd_ci
            stdout.string.strip
          end

          case format_code
          when 'i'
            expect(output).to eq('true')
          when 'j', 'k'
            expect(JSON.parse(output)).to eq(true)
          when 'p'
            expect(output).to eq('true')
          when 'y'
            expect(YAML.safe_load(output)).to eq(true)
          end
        end

        it 'formats array output correctly' do
          networks = ['Network1', 'Network2', 'Network3']
          allow(mock_model).to receive(:preferred_networks).and_return(networks)

          options = parse_options('-o', format_code, 'pr')
          cli = WifiWand::CommandLineInterface.new(options)

          output = silence_output do |stdout, _stderr|
            cli.cmd_pr
            stdout.string.strip
          end

          case format_code
          when 'i'
            expect(eval(output)).to eq(networks)
          when 'j', 'k'
            expect(JSON.parse(output)).to eq(networks)
          when 'p'
            expect(output).to eq(networks.join("\n"))
          when 'y'
            expect(YAML.safe_load(output)).to eq(networks)
          end
        end
      end
    end

    context 'without -o option (default formatting)' do
      it 'uses human-readable format for wifi info' do
        allow(mock_model).to receive(:wifi_info).and_return(test_network_info)

        options = parse_options('info')
        expect(options.post_processor).to be_nil

        cli = WifiWand::CommandLineInterface.new(options)

        output = silence_output do |stdout, _stderr|
          cli.cmd_i
          stdout.string
        end

        # Default format should be human-readable (awesome_print with key-value formatting)
        expect(output).to include('ssid')
        expect(output).to include('TestNetwork')
        # awesome_print uses => notation instead of JSON's : notation
        expect(output).to include('=>')
      end
    end

    context 'with invalid format option' do
      it 'raises configuration error' do
        expect do
          parse_options('-o', 'z', 'info')
        end.to raise_error(WifiWand::ConfigurationError, /Invalid output format/)
      end
    end

    context 'case insensitivity' do
      it 'accepts uppercase format codes' do
        options = parse_options('-o', 'J', 'info')
        expect(options.post_processor).not_to be_nil

        allow(mock_model).to receive(:wifi_info).and_return(test_network_info)
        cli = WifiWand::CommandLineInterface.new(options)

        output = silence_output do |stdout, _stderr|
          cli.cmd_i
          stdout.string.strip
        end

        # Should still parse as JSON
        expect { JSON.parse(output) }.not_to raise_error
      end

      it 'accepts mixed case format codes' do
        options = parse_options('-o', 'Y', 'info')
        expect(options.post_processor).not_to be_nil

        allow(mock_model).to receive(:wifi_info).and_return(test_network_info)
        cli = WifiWand::CommandLineInterface.new(options)

        output = silence_output do |stdout, _stderr|
          cli.cmd_i
          stdout.string.strip
        end

        # Should still parse as YAML
        expect { YAML.safe_load(output) }.not_to raise_error
      end
    end
  end

  describe 'Format-specific edge cases' do
    context 'JSON and Pretty JSON' do
      it 'Pretty JSON has more whitespace than compact JSON' do
        test_data = { 'a' => 1, 'b' => { 'c' => 2, 'd' => 3 } }
        allow(mock_model).to receive(:wifi_info).and_return(test_data)

        json_options = parse_options('-o', 'j', 'info')
        pretty_options = parse_options('-o', 'k', 'info')

        json_cli = WifiWand::CommandLineInterface.new(json_options)
        pretty_cli = WifiWand::CommandLineInterface.new(pretty_options)

        json_output = silence_output do |stdout, _stderr|
          json_cli.cmd_i
          stdout.string
        end

        pretty_output = silence_output do |stdout, _stderr|
          pretty_cli.cmd_i
          stdout.string
        end

        # Pretty JSON should have more characters due to formatting
        expect(pretty_output.length).to be > json_output.length

        # Both should parse to same structure
        expect(JSON.parse(json_output)).to eq(JSON.parse(pretty_output))

        # Pretty JSON should have newlines and indentation
        expect(pretty_output).to match(/\n/)
        expect(pretty_output).to match(/  /)
      end
    end

    context 'YAML special characters' do
      it 'properly escapes strings with special characters' do
        test_data = { 'network' => 'Test:Network', 'password' => 'has spaces & symbols!' }
        allow(mock_model).to receive(:wifi_info).and_return(test_data)

        options = parse_options('-o', 'y', 'info')
        cli = WifiWand::CommandLineInterface.new(options)

        output = silence_output do |stdout, _stderr|
          cli.cmd_i
          stdout.string.strip
        end

        parsed = YAML.safe_load(output)
        expect(parsed['network']).to eq('Test:Network')
        expect(parsed['password']).to eq('has spaces & symbols!')
      end
    end

    context 'Unicode and special characters' do
      it 'handles unicode in all formats' do
        test_data = { 'network' => '日本語ネットワーク', 'emoji' => '🔐 WiFi' }
        allow(mock_model).to receive(:wifi_info).and_return(test_data)

        ['j', 'k', 'y'].each do |format_code|
          options = parse_options('-o', format_code, 'info')
          cli = WifiWand::CommandLineInterface.new(options)

          output = silence_output do |stdout, _stderr|
            cli.cmd_i
            stdout.string.strip
          end

          parsed = case format_code
                   when 'j', 'k' then JSON.parse(output)
                   when 'y' then YAML.safe_load(output)
          end

          expect(parsed['network']).to eq('日本語ネットワーク')
          expect(parsed['emoji']).to eq('🔐 WiFi')
        end
      end
    end
  end

  describe 'Multiple commands with different formats' do
    it 'can process multiple commands in sequence with consistent formatting' do
      test_info = { 'network' => 'TestNet' }
      test_networks = ['Net1', 'Net2']

      allow(mock_model).to receive(:wifi_info).and_return(test_info)
      allow(mock_model).to receive(:preferred_networks).and_return(test_networks)

      options = parse_options('-o', 'j', 'info')
      cli = WifiWand::CommandLineInterface.new(options)

      # Execute first command
      output1 = silence_output do |stdout, _stderr|
        cli.cmd_i
        stdout.string.strip
      end

      # Execute second command with same CLI instance
      output2 = silence_output do |stdout, _stderr|
        cli.cmd_pr
        stdout.string.strip
      end

      # Both should be valid JSON
      expect { JSON.parse(output1) }.not_to raise_error
      expect { JSON.parse(output2) }.not_to raise_error

      # Validate content
      expect(JSON.parse(output1)).to eq(test_info)
      expect(JSON.parse(output2)).to eq(test_networks)
    end
  end

  describe 'Format preservation with different data types' do
    it 'maintains type information through JSON format' do
      test_data = {
        'string' => 'text',
        'integer' => 42,
        'float' => 3.14,
        'boolean' => true,
        'null' => nil,
        'array' => [1, 2, 3],
        'nested' => { 'key' => 'value' }
      }

      allow(mock_model).to receive(:wifi_info).and_return(test_data)

      options = parse_options('-o', 'j', 'info')
      cli = WifiWand::CommandLineInterface.new(options)

      output = silence_output do |stdout, _stderr|
        cli.cmd_i
        stdout.string.strip
      end

      parsed = JSON.parse(output)

      expect(parsed['string']).to be_a(String)
      expect(parsed['integer']).to be_a(Integer)
      expect(parsed['float']).to be_a(Float)
      expect(parsed['boolean']).to eq(true)
      expect(parsed['null']).to be_nil
      expect(parsed['array']).to be_a(Array)
      expect(parsed['nested']).to be_a(Hash)
    end
  end

  describe 'Output stability and reproducibility' do
    it 'produces identical output for identical input (JSON)' do
      test_data = { 'network' => 'Test', 'value' => 123 }
      allow(mock_model).to receive(:wifi_info).and_return(test_data)

      outputs = 3.times.map do
        options = parse_options('-o', 'j', 'info')
        cli = WifiWand::CommandLineInterface.new(options)
        silence_output do |stdout, _stderr|
          cli.cmd_i
          stdout.string.strip
        end
      end

      # All outputs should be identical
      expect(outputs.uniq.length).to eq(1)

      # And should parse to the same structure
      parsed_outputs = outputs.map { |o| JSON.parse(o) }
      expect(parsed_outputs.uniq.length).to eq(1)
    end
  end
end
