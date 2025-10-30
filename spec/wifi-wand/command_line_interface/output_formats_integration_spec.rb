# frozen_string_literal: true

# =============================================================================
# Output Format Integration Tests
# =============================================================================
#
# PURPOSE:
# Tests that all configurable output formats (-o i/j/k/p/y) produce valid,
# parseable output across different data types. These tests validate that
# the formatters defined in lib/wifi-wand/main.rb work correctly for the
# variety of data structures returned by CLI commands.
#
# WHAT THIS FILE TESTS:
# - All 5 output formats: inspect, JSON, pretty JSON, puts, YAML
# - Each format with various data types:
#   * Strings (network names)
#   * Booleans (wifi on/off status)
#   * Arrays (network lists, nameservers)
#   * Hashes (wifi info, nested structures)
#   * Nil values (no network connected)
#   * Empty arrays (no nameservers)
# - Output validation by parsing: JSON.parse(), YAML.safe_load(), eval()
# - Format comparison: ensures different formats produce different output
# - Round-trip serialization: data → format → parse → should equal original
# - Interactive mode behavior: returns raw objects, ignores formatters
#
# HOW IT DIFFERS FROM output_formats_e2e_spec.rb:
# - INTEGRATION focus: Tests formatters with real application processors
#   from Main class, not mock/test-defined processors
# - DATA TYPE coverage: Systematically tests each format with all data types
# - PARSE validation: Parses output back to verify correctness (JSON, YAML)
# - Unit-level: Tests individual commands with specific data types
#
# The e2e file tests the full command-line flow including argument parsing,
# edge cases (unicode, special chars), invalid inputs, and multi-command
# sequences. This file focuses on systematic data type coverage and
# validation that output can be correctly parsed and round-tripped.
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/command_line_interface'
require_relative '../../../lib/wifi-wand/main'
require 'json'
require 'yaml'

describe 'Output Format Integration Tests' do
  include TestHelpers

  let(:mock_model) { create_standard_mock_model }
  let(:mock_os) { create_mock_os_with_model(mock_model) }

  before(:each) do
    allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(mock_os)
    allow_any_instance_of(WifiWand::CommandLineInterface).to receive(:run_shell)
  end

  # Helper method to parse command line arguments and get the real application processor
  def parse_options(*args)
    stub_const('ARGV', args.dup)
    main = WifiWand::Main.new
    main.send(:parse_command_line)
  end

  describe 'Output format validation' do
    output_formats = {
      inspect: {
        code: 'i'
      },
      json: {
        code: 'j'
      },
      pretty_json: {
        code: 'k'
      },
      puts: {
        code: 'p'
      },
      yaml: {
        code: 'y'
      }
    }

    output_formats.each do |format_name, format_config|
      describe "#{format_name} format (-o #{format_config[:code]})" do

        context 'with string data' do
          let(:test_data) { 'TestNetwork' }
          let(:options) { parse_options('-o', format_config[:code], 'ne') }
          subject { WifiWand::CommandLineInterface.new(options) }

          it 'produces valid output that can be parsed' do
            allow(mock_model).to receive(:connected_network_name).and_return(test_data)

            output = silence_output do |stdout, _stderr|
              subject.cmd_ne
              stdout.string.strip
            end

            case format_name
            when :inspect
              expect(output).to eq(test_data.inspect)
            when :json
              parsed = JSON.parse(output)
              expect(parsed).to eq(test_data)
            when :pretty_json
              parsed = JSON.parse(output)
              expect(parsed).to eq(test_data)
            when :puts
              expect(output).to eq(test_data)
            when :yaml
              parsed = YAML.safe_load(output)
              expect(parsed).to eq(test_data)
            end
          end
        end

        context 'with boolean data' do
          let(:test_data) { true }
          let(:options) { parse_options('-o', format_config[:code], 'w') }
          subject { WifiWand::CommandLineInterface.new(options) }

          it 'produces valid output for true' do
            allow(mock_model).to receive(:wifi_on?).and_return(true)

            output = silence_output do |stdout, _stderr|
              subject.cmd_w
              stdout.string.strip
            end

            case format_name
            when :inspect
              expect(output).to eq('true')
            when :json
              parsed = JSON.parse(output)
              expect(parsed).to eq(true)
            when :pretty_json
              parsed = JSON.parse(output)
              expect(parsed).to eq(true)
            when :puts
              expect(output).to eq('true')
            when :yaml
              parsed = YAML.safe_load(output)
              expect(parsed).to eq(true)
            end
          end

          it 'produces valid output for false' do
            allow(mock_model).to receive(:wifi_on?).and_return(false)

            output = silence_output do |stdout, _stderr|
              subject.cmd_w
              stdout.string.strip
            end

            case format_name
            when :inspect
              expect(output).to eq('false')
            when :json
              parsed = JSON.parse(output)
              expect(parsed).to eq(false)
            when :pretty_json
              parsed = JSON.parse(output)
              expect(parsed).to eq(false)
            when :puts
              expect(output).to eq('false')
            when :yaml
              parsed = YAML.safe_load(output)
              expect(parsed).to eq(false)
            end
          end
        end

        context 'with array data' do
          let(:test_data) { ['Network1', 'Network2', 'Network3'] }
          let(:options) { parse_options('-o', format_config[:code], 'pr') }
          subject { WifiWand::CommandLineInterface.new(options) }

          it 'produces valid output that can be parsed' do
            allow(mock_model).to receive(:preferred_networks).and_return(test_data)

            output = silence_output do |stdout, _stderr|
              subject.cmd_pr
              stdout.string.strip
            end

            case format_name
            when :inspect
              expect(eval(output)).to eq(test_data)
            when :json
              parsed = JSON.parse(output)
              expect(parsed).to eq(test_data)
            when :pretty_json
              parsed = JSON.parse(output)
              expect(parsed).to eq(test_data)
              # Verify pretty formatting
              expect(output).to match(/\n/)
            when :puts
              expect(output).to eq(test_data.join("\n"))
            when :yaml
              parsed = YAML.safe_load(output)
              expect(parsed).to eq(test_data)
            end
          end
        end

        context 'with empty array data' do
          let(:test_data) { [] }
          let(:options) { parse_options('-o', format_config[:code], 'na') }
          subject { WifiWand::CommandLineInterface.new(options) }

          it 'produces valid output for empty array' do
            allow(mock_model).to receive(:nameservers).and_return(test_data)

            output = silence_output do |stdout, _stderr|
              subject.cmd_na
              stdout.string.strip
            end

            case format_name
            when :inspect
              expect(eval(output)).to eq([])
            when :json
              parsed = JSON.parse(output)
              expect(parsed).to eq([])
            when :pretty_json
              parsed = JSON.parse(output)
              expect(parsed).to eq([])
            when :puts
              # Empty array with puts produces empty output
              expect(output).to eq('')
            when :yaml
              parsed = YAML.safe_load(output)
              expect(parsed).to eq([])
            end
          end
        end

        context 'with hash data' do
          let(:test_data) { { 'ssid' => 'TestNet', 'channel' => 6, 'signal' => -50 } }
          let(:options) { parse_options('-o', format_config[:code], 'i') }
          subject { WifiWand::CommandLineInterface.new(options) }

          it 'produces valid output that can be parsed' do
            allow(mock_model).to receive(:wifi_info).and_return(test_data)

            output = silence_output do |stdout, _stderr|
              subject.cmd_i
              stdout.string.strip
            end

            case format_name
            when :inspect
              # Hash inspect format might differ between Ruby versions
              expect(output).to include('ssid')
              expect(output).to include('TestNet')
              expect(output).to include('channel')
            when :json
              parsed = JSON.parse(output)
              expect(parsed).to eq(test_data)
            when :pretty_json
              parsed = JSON.parse(output)
              expect(parsed).to eq(test_data)
              # Verify pretty formatting with newlines and indentation
              expect(output).to match(/\n/)
              expect(output).to match(/  /)
            when :puts
              # Hash puts format
              expect(output).to include('ssid')
              expect(output).to include('TestNet')
            when :yaml
              parsed = YAML.safe_load(output)
              expect(parsed).to eq(test_data)
            end
          end
        end

        context 'with nested hash data' do
          let(:test_data) do
            {
              'wifi_on' => true,
              'network' => {
                'ssid' => 'HomeNet',
                'channel' => 11,
                'security' => 'WPA2'
              },
              'ip_address' => '192.168.1.100'
            }
          end
          let(:options) { parse_options('-o', format_config[:code], 'i') }
          subject { WifiWand::CommandLineInterface.new(options) }

          it 'produces valid output for nested structures' do
            allow(mock_model).to receive(:wifi_info).and_return(test_data)

            output = silence_output do |stdout, _stderr|
              subject.cmd_i
              stdout.string.strip
            end

            case format_name
            when :inspect
              expect(output).to include('wifi_on')
              expect(output).to include('HomeNet')
              expect(output).to include('WPA2')
            when :json
              parsed = JSON.parse(output)
              expect(parsed).to eq(test_data)
              expect(parsed['network']['ssid']).to eq('HomeNet')
            when :pretty_json
              parsed = JSON.parse(output)
              expect(parsed).to eq(test_data)
              expect(parsed['network']['ssid']).to eq('HomeNet')
              # Verify pretty formatting
              expect(output).to match(/\n/)
              expect(output).to match(/  /)
            when :puts
              expect(output).to include('wifi_on')
              expect(output).to include('network')
            when :yaml
              parsed = YAML.safe_load(output)
              expect(parsed).to eq(test_data)
              expect(parsed['network']['ssid']).to eq('HomeNet')
            end
          end
        end

        context 'with nil data' do
          let(:test_data) { nil }
          let(:options) { parse_options('-o', format_config[:code], 'ne') }
          subject { WifiWand::CommandLineInterface.new(options) }

          it 'produces valid output for nil' do
            allow(mock_model).to receive(:connected_network_name).and_return(nil)

            output = silence_output do |stdout, _stderr|
              subject.cmd_ne
              stdout.string.strip
            end

            case format_name
            when :inspect
              expect(output).to eq('nil')
            when :json
              parsed = JSON.parse(output)
              expect(parsed).to be_nil
            when :pretty_json
              parsed = JSON.parse(output)
              expect(parsed).to be_nil
            when :puts
              # nil with puts produces empty string
              expect(output).to eq('')
            when :yaml
              parsed = YAML.safe_load(output)
              expect(parsed).to be_nil
            end
          end
        end
      end
    end
  end

  describe 'Format comparison tests' do
    let(:test_data) { { 'network' => 'TestNet', 'signal' => -45, 'connected' => true } }

    it 'produces different output for each format' do
      outputs = {}

      format_codes = {
        inspect: 'i',
        json: 'j',
        pretty_json: 'k',
        puts: 'p',
        yaml: 'y'
      }

      format_codes.each do |format_name, code|
        options = parse_options('-o', code, 'i')
        cli = WifiWand::CommandLineInterface.new(options)
        allow(cli.model).to receive(:wifi_info).and_return(test_data)

        outputs[format_name] = silence_output do |stdout, _stderr|
          cli.cmd_i
          stdout.string
        end
      end

      # Verify all outputs are different (except possibly some edge cases)
      expect(outputs[:json]).not_to eq(outputs[:pretty_json])  # Pretty JSON has whitespace
      expect(outputs[:json]).not_to eq(outputs[:yaml])         # Different serialization formats
      expect(outputs[:inspect]).not_to eq(outputs[:json])      # Different representations

      # Verify pretty JSON has more characters (due to formatting)
      expect(outputs[:pretty_json].length).to be > outputs[:json].length
    end
  end

  describe 'Round-trip serialization tests' do
    let(:complex_data) do
      {
        'wifi_status' => {
          'enabled' => true,
          'connected' => true,
          'network_name' => 'HomeNetwork',
          'signal_strength' => -45
        },
        'network_details' => {
          'channel' => 11,
          'frequency' => '2.4GHz',
          'security' => 'WPA2-PSK',
          'ip_address' => '192.168.1.100'
        },
        'available_networks' => ['HomeNetwork', 'GuestNetwork', 'OfficeWiFi'],
        'nameservers' => ['8.8.8.8', '8.8.4.4', '1.1.1.1']
      }
    end

    ['j', 'k', 'y'].each do |format_code|
      format_name = case format_code
                    when 'j' then 'JSON'
                    when 'k' then 'Pretty JSON'
                    when 'y' then 'YAML'
                    end

      it "can round-trip complex data through #{format_name} format" do
        options = parse_options('-o', format_code, 'i')
        cli = WifiWand::CommandLineInterface.new(options)
        allow(cli.model).to receive(:wifi_info).and_return(complex_data)

        output = silence_output do |stdout, _stderr|
          cli.cmd_i
          stdout.string.strip
        end

        # Parse the output
        parsed = case format_code
                 when 'j', 'k' then JSON.parse(output)
                 when 'y' then YAML.safe_load(output)
                 end

        # Verify round-trip preserves data
        expect(parsed).to eq(complex_data)
        expect(parsed['wifi_status']['network_name']).to eq('HomeNetwork')
        expect(parsed['network_details']['channel']).to eq(11)
        expect(parsed['available_networks']).to eq(['HomeNetwork', 'GuestNetwork', 'OfficeWiFi'])
        expect(parsed['nameservers'].length).to eq(3)
      end
    end
  end

  describe 'Interactive mode ignores output formats' do
    it 'returns raw data in interactive mode regardless of post_processor' do
      test_data = { 'network' => 'TestNet' }

      options = parse_options('-o', 'j', 'shell', 'i')
      cli = WifiWand::CommandLineInterface.new(options)
      allow(cli.model).to receive(:wifi_info).and_return(test_data)

      result = cli.cmd_i

      # In interactive mode, raw data is returned, not formatted
      expect(result).to eq(test_data)
      expect(result).not_to be_a(String)
    end
  end
end
