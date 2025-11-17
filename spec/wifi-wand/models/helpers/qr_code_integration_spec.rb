# frozen_string_literal: true

# QR Code Integration (end-to-end)
# Runs real `qrencode` and `zbarimg` if available to verify:
# - Generated files exist and are valid PNGs
# - Decoded payload matches expected WiFi components
# Unit-level arg construction (stdout/custom filespec, type flags) is covered in qr_code_generator_spec.rb

require_relative '../../../spec_helper'
require 'tempfile'
require 'fileutils'

# Integration tests that create real QR code files and verify their contents
describe 'QR Code Integration Tests' do

  before(:all) do
    # Check if required tools are available
    unless system('which qrencode > /dev/null 2>&1')
      skip 'qrencode not available - install with: sudo apt install qrencode'
    end

    unless system('which zbarimg > /dev/null 2>&1')
      skip 'zbarimg not available - install with: sudo apt install zbar-tools'
    end
  end

  let(:test_model) { create_test_model }
  let(:temp_dir) { Dir.mktmpdir('qr_test') }

  after(:each) do
    # Clean up test files
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
    Dir.glob('*-qr-code.png').each { |f| File.delete(f) }
  end

  # Helper method to decode QR code and extract content
  def decode_qr_code(filename)
    return nil unless File.exist?(filename)

    output = `zbarimg "#{filename}" 2>/dev/null`
    return nil unless $?.success?

    # Extract the QR code content (format: "QR-Code:CONTENT")
    lines = output.split("\n")
    qr_line = lines.find { |line| line.start_with?('QR-Code:') }
    qr_line ? qr_line.sub('QR-Code:', '') : nil
  end

  # Helper method to parse WiFi QR code string into components
  def parse_wifi_qr_string(qr_string)
    return nil unless qr_string&.start_with?('WIFI:') && qr_string.end_with?(';;')

    # Remove WIFI: prefix and ;; suffix
    content = qr_string[5..-3]
    components = {}

    # Split by semicolon, handling escaped characters
    parts = content.split(/(?<!\\);/)

    parts.each do |part|
      next if part.empty?

      key, value = part.split(':', 2)
      next unless key && value

      # Unescape special characters
      unescaped_value = value.gsub('\\;', ';')
                             .gsub('\\,', ',')
                             .gsub('\\:', ':')
                             .gsub('\\\\', '\\')

      components[key] = unescaped_value
    end

    components
  end

  describe 'Real QR Code Generation and Verification' do
    # Table-driven test cases
    test_cases = [
      {
        name: 'WPA2 network with password',
        network_name: 'TestNetwork',
        password: 'password123',
        security_type: 'WPA2',
        expected: {
          'T' => 'WPA',
          'S' => 'TestNetwork',
          'P' => 'password123',
          'H' => 'false'
        }
      },
      {
        name: 'WPA3 network with complex password',
        network_name: 'SecureNet-5G',
        password: 'C0mp1ex!P@ssw0rd',
        security_type: 'WPA3',
        expected: {
          'T' => 'WPA',
          'S' => 'SecureNet-5G',
          'P' => 'C0mp1ex!P@ssw0rd',
          'H' => 'false'
        }
      },
      {
        name: 'WEP network',
        network_name: 'OldRouter',
        password: '1234567890',
        security_type: 'WEP',
        expected: {
          'T' => 'WEP',
          'S' => 'OldRouter',
          'P' => '1234567890',
          'H' => 'false'
        }
      },
      {
        name: 'Open network (no password)',
        network_name: 'FreeWiFi',
        password: nil,
        security_type: nil,
        expected: {
          'T' => 'nopass',
          'S' => 'FreeWiFi',
          'P' => '',
          'H' => 'false'
        }
      },
      {
        name: 'Network name with spaces',
        network_name: 'Coffee Shop WiFi',
        password: 'welcome123',
        security_type: 'WPA2',
        expected: {
          'T' => 'WPA',
          'S' => 'Coffee Shop WiFi',
          'P' => 'welcome123',
          'H' => 'false'
        }
      },
      {
        name: 'Network with special characters in SSID',
        network_name: 'Net;work:WiFi\\Test',
        password: 'p@ss,w0rd;test:data\\escape',
        security_type: 'WPA2',
        expected: {
          'T' => 'WPA',
          'S' => 'Net;work:WiFi\\Test',
          'P' => 'p@ss,w0rd;test:data\\escape',
          'H' => 'false'
        }
      },
      {
        name: 'Long network name and password',
        network_name: 'VeryLongNetworkNameThatExceeds32Characters',
        password: 'ThisIsAVeryLongPasswordThatContainsLotsOfCharactersToTestLongStrings',
        security_type: 'WPA3',
        expected: {
          'T' => 'WPA',
          'S' => 'VeryLongNetworkNameThatExceeds32Characters',
          'P' => 'ThisIsAVeryLongPasswordThatContainsLotsOfCharactersToTestLongStrings',
          'H' => 'false'
        }
      }
    ]

    test_cases.each do |test_case|
      it "creates valid QR code for #{test_case[:name]}" do
        # Setup model mocks to prevent real system calls
        allow(test_model).to receive(:command_available?).with('qrencode').and_return(true)
        allow(test_model).to receive(:connected_network_name).and_return(test_case[:network_name])
        allow(test_model).to receive(:connected_network_password).and_return(test_case[:password])
        allow(test_model).to receive(:connection_security_type).and_return(test_case[:security_type])

        # Mock methods that could make real system calls
        allow(test_model).to receive(:preferred_networks).and_return([test_case[:network_name]])
        allow(test_model).to receive(:preferred_network_password).and_return(test_case[:password])
        allow(test_model).to receive(:_preferred_network_password).and_return(test_case[:password])

        # Don't mock run_os_command - let it create real QR code files
        allow(test_model).to receive(:run_os_command) do |cmd|
          system(*cmd) if cmd.is_a?(Array) && cmd[0] == 'qrencode'
          command_result(stdout: '')
        end

        # Generate QR code
        filename = silence_output { test_model.generate_qr_code }
        expect(File.exist?(filename)).to be true

        # Decode and verify QR code content
        decoded_content = decode_qr_code(filename)
        expect(decoded_content).not_to be_nil, "Failed to decode QR code from #{filename}"

        # Parse WiFi QR string
        wifi_components = parse_wifi_qr_string(decoded_content)
        expect(wifi_components).not_to be_nil, "Failed to parse WiFi QR string: #{decoded_content}"

        # Verify each expected component
        test_case[:expected].each do |key, expected_value|
          actual_value = wifi_components[key]
          expect(actual_value).to eq(expected_value),
            "QR component '#{key}' mismatch. Expected: '#{expected_value}', Got: '#{actual_value}'"
        end

        # Verify filename format
        safe_network_name = test_case[:network_name].gsub(/[^\w\-_]/, '_')
        expected_filename = "#{safe_network_name}-qr-code.png"
        expect(filename).to eq(expected_filename)

        # Verify file is a valid PNG
        file_type = `file "#{filename}"`.strip
        expect(file_type).to include('PNG image')

        # Clean up
        File.delete(filename) if File.exist?(filename)
      end
    end
  end

  describe 'QR Code Error Handling' do
    it 'handles qrencode command failure gracefully' do
      allow(test_model).to receive(:command_available?).with('qrencode').and_return(true)
      allow(test_model).to receive(:connected_network_name).and_return('TestNetwork')
      allow(test_model).to receive(:connected_network_password).and_return('password')
      allow(test_model).to receive(:connection_security_type).and_return('WPA2')

      # Mock methods that could make real system calls
      allow(test_model).to receive(:preferred_networks).and_return(['TestNetwork'])
      allow(test_model).to receive(:preferred_network_password).and_return('password')
      allow(test_model).to receive(:_preferred_network_password).and_return('password')

      # Mock qrencode to fail
      allow(test_model).to receive(:run_os_command) do |cmd|
        if cmd.is_a?(Array) && cmd[0] == 'qrencode'
          raise WifiWand::CommandExecutor::OsCommandError.new(1, cmd.join(' '), 
'Simulated qrencode failure')
        else
          command_result(stdout: '')
        end
      end

      expect { silence_output {
 test_model.generate_qr_code } }.to raise_error(WifiWand::Error, /Failed to generate QR code/)
    end
  end

  describe 'QR Code File Properties' do
    it 'creates QR codes with reasonable file sizes' do
      allow(test_model).to receive(:command_available?).with('qrencode').and_return(true)
      allow(test_model).to receive(:connected_network_name).and_return('TestNetwork')
      allow(test_model).to receive(:connected_network_password).and_return('password123')
      allow(test_model).to receive(:connection_security_type).and_return('WPA2')

      # Mock methods that could make real system calls
      allow(test_model).to receive(:preferred_networks).and_return(['TestNetwork'])
      allow(test_model).to receive(:preferred_network_password).and_return('password123')
      allow(test_model).to receive(:_preferred_network_password).and_return('password123')

      allow(test_model).to receive(:run_os_command) do |cmd|
        if cmd.is_a?(Array) && cmd[0] == 'qrencode'
          system(*cmd)
          command_result(stdout: '')
        else
          command_result(stdout: '')
        end
      end

      filename = silence_output { test_model.generate_qr_code }

      expect(File.exist?(filename)).to be true
      file_size = File.size(filename)

      # QR codes should be reasonable size (typically 200-2000 bytes for simple WiFi info)
      expect(file_size).to be > 100, "QR code file too small: #{file_size} bytes"
      expect(file_size).to be < 10_000, "QR code file too large: #{file_size} bytes"

      File.delete(filename) if File.exist?(filename)
    end
  end

  describe 'QR Code Robustness' do
    it 'creates scannable QR codes for various WiFi configurations' do
      configurations = [
        { ssid: 'Test', password: '', security: nil },           # Open
        { ssid: 'A', password: '1', security: 'WPA2' },         # Minimal
        { ssid: 'Test-Network_123', password: 'P@ssw0rd!', security: 'WPA3' }, # Complex
      ]

      configurations.each do |config|
        allow(test_model).to receive(:command_available?).with('qrencode').and_return(true)
        allow(test_model).to receive(:connected_network_name).and_return(config[:ssid])
        allow(test_model).to receive(:connected_network_password).and_return(config[:password])
        allow(test_model).to receive(:connection_security_type).and_return(config[:security])

        # Mock methods that could make real system calls
        allow(test_model).to receive(:preferred_networks).and_return([config[:ssid]])
        allow(test_model).to receive(:preferred_network_password).and_return(config[:password])
        allow(test_model).to receive(:_preferred_network_password).and_return(config[:password])

        allow(test_model).to receive(:run_os_command) do |cmd|
          system(*cmd) if cmd.is_a?(Array) && cmd[0] == 'qrencode'
          command_result(stdout: '')
        end

        filename = silence_output { test_model.generate_qr_code }

        # Verify QR code can be decoded
        decoded_content = decode_qr_code(filename)
        expect(decoded_content).not_to be_nil, "Failed to decode QR code for SSID: #{config[:ssid]}"

        # Verify it's a valid WiFi QR string
        expect(decoded_content).to start_with('WIFI:')
        expect(decoded_content).to end_with(';;')

        File.delete(filename) if File.exist?(filename)
      end
    end
  end
end

# Separate tests for stdout text and custom filespec output, kept in this main
# QR spec file for cohesion but independent of external zbar tools.
## Unit tests for stdout/custom filespec live in qr_code_generator_spec.rb
