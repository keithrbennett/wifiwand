# frozen_string_literal: true

require 'json'
require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/models/mac_os_model'

module WifiWand
  describe MacOsModel, :os_mac do
    
    # Prevent accidental Keychain UI prompts in all tests (both disruptive and non-disruptive)
    before(:each) do
      # Mock network connectivity tester to prevent real network calls during non-disruptive tests
      # Check if current test or any parent group is marked as disruptive
      example_disruptive = RSpec.current_example&.metadata[:disruptive]
      group_disruptive = RSpec.current_example&.example_group&.metadata[:disruptive]
      is_disruptive = example_disruptive || group_disruptive
      
      unless is_disruptive || RSpec.current_example&.metadata[:keychain_integration]
        # Avoid macOS Keychain prompts during non-disruptive tests
        allow_any_instance_of(WifiWand::MacOsModel).to receive(:preferred_network_password).and_return(nil)
        # Ensure initialization doesn’t fail due to interface detection during non-disruptive tests
        allow_any_instance_of(WifiWand::MacOsModel).to receive(:detect_wifi_interface).and_return('en0')

        allow_any_instance_of(WifiWand::NetworkConnectivityTester).to receive(:connected_to_internet?).and_return(true)
        allow_any_instance_of(WifiWand::NetworkConnectivityTester).to receive(:tcp_connectivity?).and_return(true)
        allow_any_instance_of(WifiWand::NetworkConnectivityTester).to receive(:dns_working?).and_return(true)

      end
    end
    
    describe "version support" do
      subject(:model) { create_mac_os_test_model }

      it "compares version strings correctly" do
        test_cases = [
          ["12.0",     true,  "identical"],
          ["12.1",     true,  "newer minor"],
          ["13.0",     true,  "newer major"],
          ["11.6",     false, "older minor"],
          ["11.0",     false, "older major"],
          ["12.0.1",   true,  "patch version"],
          ["12",       true,  "short format"]
        ]

        test_cases.each do |version, expected, description|
          result = model.send(:supported_version?, version)
          expect(result).to eq(expected),
                            "Version #{version} (#{description}): expected #{expected}, got #{result}"
        end
      end

      context "with current macOS version" do
        it "validates current version meets minimum requirement" do
          current_version = model.instance_variable_get(:@macos_version)
          skip "macOS version not detected" unless current_version

          result = model.send(:supported_version?, current_version)
          expect(result).to be(true), "Current version #{current_version} should be supported"
        end
      end

      context "basic validation" do
        it "validates supported version detection" do
          expect(model.send(:supported_version?, "12.0")).to be true
          expect(model.send(:supported_version?, "11.6")).to be false
        end

        it "handles invalid inputs gracefully" do
          expect(model.send(:supported_version?, nil)).to be false
        end
      end

      context "#validate_macos_version" do
        it "accepts supported versions" do
          model = create_mac_os_test_model
          model.instance_variable_set(:@macos_version, "12.0")
          expect { model.send(:validate_macos_version) }.not_to raise_error
        end

        it "rejects unsupported versions" do
          model = create_mac_os_test_model
          model.instance_variable_set(:@macos_version, "11.6")
          expect { model.send(:validate_macos_version) }.to raise_error(WifiWand::UnsupportedSystemError)
        end

        it "handles nil version gracefully" do
          model = create_mac_os_test_model
          model.instance_variable_set(:@macos_version, nil)
          expect { model.send(:validate_macos_version) }.not_to raise_error
        end
      end

      context "#detect_macos_version" do
        it "detects macOS version when command succeeds" do
          model = create_mac_os_test_model
          allow(model).to receive(:run_os_command).with(%w[sw_vers -productVersion]).and_return(command_result(stdout: "15.6\n"))
          expect(model.send(:detect_macos_version)).to eq("15.6")
        end

        it "returns nil when command fails" do
          model = create_mac_os_test_model
          allow(model).to receive(:run_os_command).with(%w[sw_vers -productVersion]).and_raise(StandardError.new("Command failed"))
          expect { model.send(:detect_macos_version) }.not_to raise_error
          expect(model.send(:detect_macos_version)).to be_nil
        end
      end

      # System-modifying tests (will change wifi state)
      context 'system-modifying operations', :disruptive do
        subject { create_mac_os_test_model }

        describe '#wifi_on' do
          it 'turns wifi on when it is off' do
            subject.wifi_off
            expect(subject.wifi_on?).to be(false)

            subject.wifi_on
            expect(subject.wifi_on?).to be(true)
          end
        end

        describe '#wifi_off' do
          it 'turns wifi off when it is on' do
            subject.wifi_on
            expect(subject.wifi_on?).to be(true)

            subject.wifi_off
            expect(subject.wifi_on?).to be(false)
          end
        end

        describe '#disconnect' do
          it 'disconnects from current network', :needs_sudo_access do
            expect { subject.disconnect }.not_to raise_error
            expect { subject.disconnect }.not_to raise_error
          end
        end

        describe '#remove_preferred_network' do
          it 'handles removal of non-existent network', :needs_sudo_access do
            expect { subject.remove_preferred_network('non_existent_network_123') }.not_to raise_error
          end
        end
      end

      # Network connection tests (highest risk)
      context 'network connection operations', :disruptive do
        subject { create_mac_os_test_model }

        describe '#_connect' do
          it 'raises error for non-existent network' do
            # Swift command exits with status 1 and "Error: Network not found" message
            expect { subject._connect('non_existent_network_123') }.to raise_error(WifiWand::CommandExecutor::OsCommandError)
          end
        end
      end

      # Additional disruptive tests for system-modifying operations
      context 'extended disruptive operations', :disruptive do
        subject { create_mac_os_test_model }
        
        before(:all) do
          @original_nameservers = nil
          @original_wifi_state = nil
        end

        before(:each) do
          # Capture current state for restoration
          @original_wifi_state = subject.wifi_on? rescue true
          # Capture DNS using networksetup to focus on Wi‑Fi service configuration
          @original_nameservers = subject.nameservers_using_networksetup rescue []
        end

        after(:each) do
          # Restore original state
          begin
            if @original_wifi_state
              subject.wifi_on
            else
              subject.wifi_off
            end
            subject.set_nameservers(@original_nameservers) if @original_nameservers.any?
          rescue => e
            puts "Warning: Failed to restore system state: #{e.message}"
          end
        end

        describe '#wifi_on?' do
          it 'accurately reports WiFi status after state changes' do
            test_scenarios = [
              [:wifi_on, true],
              [:wifi_off, false],
              [:wifi_on, true]
            ]

            test_scenarios.each do |method, expected_state|
              subject.public_send(method)
              expect(subject.wifi_on?).to eq(expected_state), 
                     "WiFi should be #{expected_state ? 'on' : 'off'} after #{method}"
            end
          end
        end

        describe '#set_nameservers' do
          let(:test_nameservers) { ['8.8.8.8', '1.1.1.1'] }
          let(:alternate_nameservers) { ['9.9.9.9'] }

          it 'successfully sets and retrieves nameservers' do
            # Set test nameservers
            subject.set_nameservers(test_nameservers)

            # Poll until the new nameservers appear
            wait_for(timeout: 30, interval: 0.5, description: "nameservers to be set") do
              (test_nameservers - subject.nameservers_using_networksetup).empty?
            end

            expect((test_nameservers - subject.nameservers_using_networksetup).empty?).to be(true)
          end

          it 'handles nameserver clearing and restoration' do
            # Clear nameservers, then immediately set new ones
            subject.set_nameservers(:clear)
            subject.set_nameservers(alternate_nameservers)

            # Wait for the new ones to be applied
            wait_for(timeout: 30, interval: 0.5, description: "alternate nameservers to be set") do
              subject.nameservers_using_networksetup.include?(alternate_nameservers.first)
            end
            expect(subject.nameservers_using_networksetup).to include(alternate_nameservers.first)
          end

          it 'validates IP address format before setting' do
            invalid_scenarios = [
              ['invalid.ip.address'],
              ['999.999.999.999'],
              ['not.an.ip', '8.8.8.8'],
              ['192.168.1.1', 'bad.ip']
            ]

            invalid_scenarios.each do |invalid_nameservers|
              expect { subject.set_nameservers(invalid_nameservers) }
                .to raise_error(WifiWand::InvalidIPAddressError),
                     "Should reject invalid nameservers: #{invalid_nameservers}"
            end
          end
        end

        describe 'WiFi state consistency' do
          it 'maintains consistent state across multiple operations' do
            operations = [
              -> { subject.wifi_off },
              -> { expect(subject.wifi_on?).to be(false) },
              -> { subject.wifi_on },
              -> { expect(subject.wifi_on?).to be(true) },
              -> { subject.disconnect },
              -> { expect(subject.wifi_on?).to be(true) } # Should still be on after disconnect
            ]

            operations.each_with_index do |operation, index|
              expect { operation.call }.not_to raise_error,
                     "Operation #{index + 1} should succeed"
            end
          end
        end

        describe 'interface detection consistency' do
          it 'consistently detects same WiFi interface across calls' do
            first_interface = subject.wifi_interface
            expect(first_interface).not_to be_nil
            expect(first_interface).to match(/^en\d+$/)

            # Multiple calls should return same interface (cached)
            2.times do
              expect(subject.wifi_interface).to eq(first_interface)
            end
          end

          it 'detects WiFi service name consistently' do
            first_service = subject.detect_wifi_service_name
            expect(first_service).not_to be_nil
            
            # Multiple calls should return same service name (cached)
            2.times do
              expect(subject.detect_wifi_service_name).to eq(first_service)
            end
          end
        end

        describe 'system information gathering' do
          it 'retrieves consistent MAC address' do
            mac1 = subject.mac_address
            mac2 = subject.mac_address
            
            expect(mac1).to match(/^([0-9a-f]{2}:){5}[0-9a-f]{2}$/i)
            expect(mac1).to eq(mac2)
          end

          it 'retrieves system version information' do
            version = subject.macos_version
            if version
              expect(version).to match(/^\d+\.\d+/)
              expect(subject.send(:supported_version?, version)).to be(true)
            else
              skip "macOS version detection failed"
            end
          end
        end

        describe 'error resilience' do
          it 'handles temporary network unavailability gracefully' do
            # Turn WiFi off temporarily
            subject.wifi_off
            
            # These should not crash even with WiFi off
            expect { subject._ip_address }.not_to raise_error
            expect { subject._connected_network_name }.not_to raise_error
            expect { subject.default_interface }.not_to raise_error
            
            # Restore WiFi
            subject.wifi_on
          end
        end
      end
    end

    # Non-disruptive tests for core functionality
    context 'core functionality' do
      subject(:model) { create_mac_os_test_model }
      let(:success_result) do
        WifiWand::CommandExecutor::OsCommandResult.new(
          stdout: "", stderr: "", combined_output: "", exitstatus: 0, command: "", duration: 0.1
        )
      end

      describe '#os_id' do
        it 'returns mac symbol' do
          expect(MacOsModel.os_id).to eq(:mac)
        end
      end

  describe '#detect_wifi_service_name' do
        let(:networksetup_output) do
          "Hardware Port: Ethernet\nDevice: en1\nEthernet Address: aa:bb:cc:dd:ee:ff\n\nHardware Port: Wi-Fi\nDevice: en0\nEthernet Address: ac:bc:32:b9:a9:9d"
        end

        it 'detects common WiFi service patterns' do
          test_cases = [
            ["Hardware Port: Wi-Fi\nDevice: en0", "Wi-Fi"],
            ["Hardware Port: AirPort\nDevice: en0", "AirPort"],
            ["Hardware Port: Wireless\nDevice: en0", "Wireless"],
            ["Hardware Port: WiFi\nDevice: en0", "WiFi"],
            ["Hardware Port: WLAN\nDevice: en0", "WLAN"]
          ]

          test_cases.each do |output, expected|
            # Clear any cached value and mock the command
            model.instance_variable_set(:@wifi_service_name, nil)
            allow(model).to receive(:run_os_command).with(%w[networksetup -listallhardwareports]).and_return(command_result(stdout: output))
            expect(model.detect_wifi_service_name).to eq(expected)
          end
        end

        it 'falls back to Wi-Fi when no pattern matches' do
          no_wifi_output = "Hardware Port: Ethernet\nDevice: en1"
          allow(model).to receive(:run_os_command).with(%w[networksetup -listallhardwareports]).and_return(command_result(stdout: no_wifi_output))
          allow(model).to receive(:wifi_interface).and_return("en0")
          expect(model.detect_wifi_service_name).to eq("Wi-Fi")
        end

        it 'derives service name from previous Hardware Port line for detected interface' do
          # Ensure cache does not interfere
          model.instance_variable_set(:@wifi_service_name, nil)
          output = "Hardware Port: SpecialWifi\nDevice: en0\nEthernet Address: aa:bb:cc:dd:ee:ff\n\nHardware Port: Ethernet\nDevice: en1\n"
          allow(model).to receive(:run_os_command).with(%w[networksetup -listallhardwareports]).and_return(command_result(stdout: output))
          allow(model).to receive(:wifi_interface).and_return("en0")
          expect(model.detect_wifi_service_name).to eq("SpecialWifi")
        end
      end

      describe '#is_wifi_interface?' do
        it 'correctly identifies WiFi interfaces' do
          test_cases = [
            ["en0", nil, true],   # WiFi interface (command succeeds)
            ["en1", 10, false],   # Non-WiFi interface (exit code 10)
            ["en2", 5, true]      # WiFi interface (other non-10 exit code)
          ]

          test_cases.each do |interface, exit_status, expected|
            if exit_status
              # Mock command failure with specific exit code
              error = WifiWand::CommandExecutor::OsCommandError.new(exit_status, "networksetup", "")
              allow(model).to receive(:run_os_command).and_raise(error)
            else
              # Mock command success
              allow(model).to receive(:run_os_command).and_return(command_result(stdout: ""))
            end
            
            expect(model.is_wifi_interface?(interface)).to eq(expected)
          end
        end
      end

      describe '#detect_wifi_interface_using_networksetup' do
        it 'extracts WiFi interface from networksetup output' do
          output = "Hardware Port: Wi-Fi\nDevice: en0\nEthernet Address: aa:bb:cc\n\nHardware Port: Ethernet\nDevice: en1\n"
          allow(model).to receive(:run_os_command).with(%w[networksetup -listallhardwareports]).and_return(command_result(stdout: output))
          # Also exercise dynamic service name path
          allow(model).to receive(:detect_wifi_service_name).and_call_original
          expect(model.detect_wifi_interface_using_networksetup).to eq("en0")
        end

        it 'raises WifiInterfaceError when WiFi service not found' do
          output = "Hardware Port: Ethernet\nDevice: en1\n"
          allow(model).to receive(:run_os_command).with(%w[networksetup -listallhardwareports]).and_return(command_result(stdout: output))
          allow(model).to receive(:detect_wifi_service_name).and_return("Wi-Fi")
          expect { model.detect_wifi_interface_using_networksetup }.to raise_error(WifiWand::WifiInterfaceError)
        end
      end

      

      describe '#_ip_address' do
        it 'handles different ipconfig responses' do
          test_cases = [
            ["192.168.1.100\n", "192.168.1.100"],  # Valid IP
            ["10.0.0.5", "10.0.0.5"],              # No newline
            [WifiWand::CommandExecutor::OsCommandError.new(1, "ipconfig", ""), nil], # Interface down
          ]

          test_cases.each do |response, expected|
            if response.is_a?(Exception)
              allow(model).to receive(:run_os_command).and_raise(response)
            else
              allow(model).to receive(:run_os_command).and_return(command_result(stdout: response))
            end

            expect(model._ip_address).to eq(expected)
          end
        end

        it 're-raises unexpected ipconfig errors' do
          allow(model).to receive(:wifi_interface).and_return("en0")
          allow(model).to receive(:run_os_command).and_raise(WifiWand::CommandExecutor::OsCommandError.new(2, "ipconfig", "boom"))
          expect { model._ip_address }.to raise_error(WifiWand::CommandExecutor::OsCommandError)
        end
      end

      describe '#nameservers_using_networksetup' do
        it 'parses networksetup DNS output correctly' do
          test_cases = [
            ["8.8.8.8\n1.1.1.1\n", ["8.8.8.8", "1.1.1.1"]],
            ["There aren't any DNS Servers set on Wi-Fi.\n", []],
            ["192.168.1.1", ["192.168.1.1"]]
          ]

          test_cases.each do |output, expected|
            allow(model).to receive(:detect_wifi_service_name).and_return("Wi-Fi")
            allow(model).to receive(:run_os_command).and_return(command_result(stdout: output))
            expect(model.nameservers_using_networksetup).to eq(expected)
          end
        end
      end

      describe '#nameservers_using_scutil' do
        it 'extracts unique nameservers from scutil output' do
          scutil_output = <<~OUTPUT
            resolver #1
              domain   : local
              options  : mdns
              timeout  : 5
              nameserver[0] : 8.8.8.8
              nameserver[1] : 1.1.1.1
              flags    : Request A records
            resolver #2
              nameserver[0] : 8.8.8.8
              nameserver[1] : 9.9.9.9
          OUTPUT

          allow(model).to receive(:run_os_command).with(%w[scutil --dns]).and_return(command_result(stdout: scutil_output))
          result = model.nameservers_using_scutil
          expect(result).to contain_exactly("8.8.8.8", "1.1.1.1", "9.9.9.9")
        end
      end

        describe '#set_nameservers' do
          it 'handles different nameserver configurations' do
            test_cases = [
              { input: ["8.8.8.8", "1.1.1.1"], expected_args: ["8.8.8.8", "1.1.1.1"] },
              { input: ["192.168.1.1"], expected_args: ["192.168.1.1"] },
              { input: :clear, expected_args: ["empty"] }
            ]

            test_cases.each do |tc|
              allow(model).to receive(:detect_wifi_service_name).and_return("Wi-Fi")
              if tc[:input] == :clear
                expect(model).to receive(:run_os_command).with(['networksetup', '-setdnsservers', 'Wi-Fi', 'empty'])
              else
                expect(model).to receive(:run_os_command).with(['networksetup', '-setdnsservers', 'Wi-Fi'] + tc[:input])
              end
              expect(model.set_nameservers(tc[:input])).to eq(tc[:input])
            end
          end

        it 'validates IP addresses and raises error for invalid ones' do
          invalid_nameservers = ["8.8.8.8", "invalid.ip", "1.1.1.1"]
          silence_output do
            expect { model.set_nameservers(invalid_nameservers) }.to raise_error(WifiWand::InvalidIPAddressError)
          end
        end
      end

      describe '#swift_and_corewlan_present?' do
        it 'detects Swift/CoreWLAN availability' do
          test_cases = [
            [nil, true],  # Command succeeds
            [WifiWand::CommandExecutor::OsCommandError.new(127, "swift", ""), false], # Swift not found
            [WifiWand::CommandExecutor::OsCommandError.new(1, "swift", ""), false],   # CoreWLAN not available
            [WifiWand::CommandExecutor::OsCommandError.new(2, "swift", ""), false]    # Other error
          ]

          test_cases.each do |error, expected|
            if error
              allow(model).to receive(:run_os_command).and_raise(error)
            else
              allow(model).to receive(:run_os_command).and_return(command_result(stdout: ""))
            end

            expect(model.swift_and_corewlan_present?).to eq(expected)
          end
        end
      end

      describe '#default_interface' do
        it 'extracts default interface from route output' do
          test_cases = [
            ["   interface: en0\n", "en0"],
            ["   interface: wlan0", "wlan0"],
            ["", nil],
            [WifiWand::CommandExecutor::OsCommandError.new(1, "route", ""), nil]
          ]

          test_cases.each do |response, expected|
            if response.is_a?(Exception)
              allow(model).to receive(:run_os_command).with(%w[route -n get default], false).and_raise(response)
            else
              allow(model).to receive(:run_os_command).with(%w[route -n get default], false).and_return(command_result(stdout: response))
            end

            expect(model.default_interface).to eq(expected)
          end
        end
      end

      describe '#mac_address' do
        it 'extracts MAC address from ifconfig output' do
          ifconfig_output = "en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500\n\tether ac:bc:32:b9:a9:9d\n"
          allow(model).to receive(:wifi_interface).and_return("en0")
          allow(model).to receive(:run_os_command).with(['ifconfig', 'en0']).and_return(command_result(stdout: ifconfig_output))
          expect(model.mac_address).to eq("ac:bc:32:b9:a9:9d")
        end
      end

      describe '#remove_preferred_network' do
        it 'constructs a correctly escaped removal command for various network names' do
          allow(model).to receive(:wifi_interface).and_return('en0')

          test_cases = {
            'Simple' => "sudo networksetup -removepreferredwirelessnetwork en0 Simple",
            'Network With Spaces' => "sudo networksetup -removepreferredwirelessnetwork en0 Network\\ With\\ Spaces",
            'Network"WithQuotes' => "sudo networksetup -removepreferredwirelessnetwork en0 Network\\\"WithQuotes",
            "Network'WithSingleQuotes" => "sudo networksetup -removepreferredwirelessnetwork en0 Network\\'WithSingleQuotes"
          }

          test_cases.each do |network_name, expected_command_str|
            expected_command_array = Shellwords.split(expected_command_str)
            expect(model).to receive(:run_os_command).with(expected_command_array)
            model.remove_preferred_network(network_name)
          end
        end
      end

      describe '#open_application' do
        it 'constructs open commands properly' do
          test_cases = [
            "Safari",
            "Network Utility", 
            "App with spaces"
          ]

          test_cases.each do |app_name|
            expect(model).to receive(:run_os_command) do |cmd_array|
              expect(cmd_array[0]).to eq("open")
              expect(cmd_array[1]).to eq("-a")
              expect(cmd_array[2]).to eq(app_name)
            end
            model.open_application(app_name)
          end
        end
      end

      describe '#open_resource' do
        it 'constructs open commands properly' do
          test_cases = [
            "http://example.com",
            "file:///path with spaces/file.txt",
            "/Applications/Safari.app"
          ]

          test_cases.each do |resource|
            expect(model).to receive(:run_os_command) do |cmd_array|
              expect(cmd_array[0]).to eq("open")
              expect(cmd_array[1]).to eq(resource)
            end
            model.open_resource(resource)
          end
        end
      end

      describe '#detect_wifi_interface' do
        # Restore original method behavior for these specific tests
        before(:each) do
          allow_any_instance_of(WifiWand::MacOsModel).to receive(:detect_wifi_interface).and_call_original
          # Force fallback path to system_profiler for deterministic tests
          allow_any_instance_of(WifiWand::MacOsModel).to receive(:detect_wifi_interface_using_networksetup).and_return(nil)
        end
        # Provide a valid interface during initialization to avoid init failures in this block
        subject(:model) { create_mac_os_test_model(wifi_interface: 'en0') }
        let(:system_profiler_output) do
          {
            "SPNetworkDataType" => [
              {"_name" => "Ethernet", "interface" => "en1"},
              {"_name" => "Wi-Fi", "interface" => "en0"},
              {"_name" => "Bluetooth PAN", "interface" => "en3"}
            ]
          }.to_json
        end

        it 'detects WiFi interface from system_profiler' do
          allow(model).to receive(:detect_wifi_service_name).and_return("Wi-Fi")
          allow(model).to receive(:run_os_command).and_return(command_result(stdout: system_profiler_output))
          expect(model.detect_wifi_interface).to eq("en0")
        end

        it 'returns nil when WiFi service not found' do
          allow(model).to receive(:detect_wifi_service_name).and_return("Wi-Fi")
          allow(model).to receive(:run_os_command).and_return(command_result(stdout: '{"SPNetworkDataType": []}'))
          expect(model.detect_wifi_interface).to be_nil
        end

        it 'handles JSON parse errors gracefully' do
          allow(model).to receive(:detect_wifi_service_name).and_return("Wi-Fi")
          allow(model).to receive(:run_os_command).and_return(command_result(stdout: "invalid json"))
          expect { model.detect_wifi_interface }.to raise_error(JSON::ParserError)
        end
      end

      describe '#_preferred_network_password' do
        it 'handles different keychain scenarios' do
          test_cases = [
            [WifiWand::CommandExecutor::OsCommandError.new(44, "security", ""), nil], # Not found
            [WifiWand::CommandExecutor::OsCommandError.new(45, "security", ""), WifiWand::KeychainAccessDeniedError],
            [WifiWand::CommandExecutor::OsCommandError.new(128, "security", ""), WifiWand::KeychainAccessCancelledError],
            [WifiWand::CommandExecutor::OsCommandError.new(51, "security", ""), WifiWand::KeychainNonInteractiveError],
            [WifiWand::CommandExecutor::OsCommandError.new(25, "security", ""), WifiWand::KeychainError],
            [WifiWand::CommandExecutor::OsCommandError.new(1, "security", "could not be found"), nil],
            [WifiWand::CommandExecutor::OsCommandError.new(1, "security", "other error"), WifiWand::KeychainError],
            ["mypassword123", "mypassword123"]
          ]

          test_cases.each do |response, expected|
            if response.is_a?(Exception)
              allow(model).to receive(:run_os_command).and_raise(response)
            else
              allow(model).to receive(:run_os_command).and_return(command_result(stdout: response))
            end

            if expected.is_a?(Class) && expected < Exception
              expect { model._preferred_network_password("TestNetwork") }.to raise_error(expected)
            else
              expect(model._preferred_network_password("TestNetwork")).to eq(expected)
            end
          end
        end

        it 'raises detailed KeychainError for unknown exit codes' do
          error = WifiWand::CommandExecutor::OsCommandError.new(99, "security", "strange failure")
          allow(model).to receive(:run_os_command).and_raise(error)
          expect { model._preferred_network_password("TestNet") }.to raise_error(WifiWand::KeychainError)
        end
      end

      # Runs early to surface any auth prompts before the long suite.
      describe 'preferred_network_password command integration', :keychain_integration do
        it 'invokes security find-generic-password with correct arguments and handles not-found' do
          model = create_mac_os_test_model
          ssid = 'TestNet'

          # Ensure the network is considered preferred so wrapper calls the private method
          allow(model).to receive(:preferred_networks).and_return([ssid])

          expected_cmd = ['security', 'find-generic-password', '-D', 'AirPort network password', '-a', ssid, '-w']
          # Expect exact command, but avoid real execution by raising "not found" (exit 44)
          call_sequence = []
          allow(model).to receive(:run_os_command) do |command|
            call_sequence << command
            if command == expected_cmd
              raise WifiWand::CommandExecutor::OsCommandError.new(44, 'security', '')
            else
              command_result(stdout: 'Wi-Fi Power (en0): On')
            end
          end

          expect(model.preferred_network_password(ssid)).to be_nil
          expect(call_sequence).to include(expected_cmd)
        end
      end

      describe '#macos_version' do
        it 'handles version detection failure gracefully' do
          # Allow all other commands to execute normally
          allow_any_instance_of(WifiWand::MacOsModel).to receive(:run_os_command).and_call_original
          # Cause only the sw_vers call to fail; detection should rescue and set nil
          allow_any_instance_of(WifiWand::MacOsModel)
            .to receive(:run_os_command).with(%w[sw_vers -productVersion]).and_raise(StandardError.new("Command failed"))
          failing_model = create_mac_os_test_model
          silence_output { expect(failing_model.macos_version).to be_nil }
        end
      end

      describe '#macos_version (real system)', :os_mac, :disruptive do
        # For these real-system checks, allow actual OS command execution
        before(:each) do
          allow_any_instance_of(WifiWand::MacOsModel).to receive(:run_os_command).and_call_original
        end
        it 'returns a non-empty semantic version on macOS' do
          real_model = create_mac_os_test_model
          v = real_model.macos_version
          expect(v).to match(/^\d+\.\d+(\.\d+)?$/)
        end

        it 'meets the minimum supported version and validates without error' do
          real_model = create_mac_os_test_model
          v = real_model.macos_version
          expect(v).to match(/^\d+\.\d+(\.\d+)?$/)
          expect(real_model.send(:supported_version?, v)).to be(true)
          expect { real_model.send(:validate_macos_version) }.not_to raise_error
        end
      end

      describe '#_disconnect' do
        it 'falls back to ifconfig after Swift failure and returns nil' do
          allow(model).to receive(:swift_and_corewlan_present?).and_return(true)
          allow(model).to receive(:run_swift_command).and_raise(StandardError.new("swift failed"))
          allow(model).to receive(:wifi_interface).and_return("en0")

          # First attempt with sudo fails
          expect(model).to receive(:run_os_command).with(%w[sudo ifconfig en0 disassociate], false).and_raise(WifiWand::CommandExecutor::OsCommandError.new(1, "ifconfig", ""))
          # Fallback without sudo succeeds
          expect(model).to receive(:run_os_command).with(%w[ifconfig en0 disassociate], false).and_return(command_result(stdout: ""))

          expect(model._disconnect).to be_nil
        end

        it 'uses ifconfig path when Swift not available' do
          allow(model).to receive(:swift_and_corewlan_present?).and_return(false)
          allow(model).to receive(:wifi_interface).and_return("en0")

          expect(model).to receive(:run_os_command).with(%w[sudo ifconfig en0 disassociate], false).and_raise(WifiWand::CommandExecutor::OsCommandError.new(1, "ifconfig", ""))
          expect(model).to receive(:run_os_command).with(%w[ifconfig en0 disassociate], false).and_return(command_result(stdout: ""))

          expect(model._disconnect).to be_nil
        end
      end

      describe '#swift_and_corewlan_present?' do
        it 'handles unexpected errors gracefully and returns false' do
          allow(model).to receive(:run_os_command).and_raise(StandardError.new("unexpected"))
          expect(model.swift_and_corewlan_present?).to be(false)
        end
      end

      describe '#validate_os_preconditions' do
        it 'warns when swift is unavailable and returns :ok' do
          allow(model).to receive(:command_available?).with("swift").and_return(false)
          expect(model.validate_os_preconditions).to eq(:ok)
        end
      end

      describe '#preferred_networks' do
        it 'parses and sorts preferred networks correctly' do
          networksetup_output = "Preferred networks on en0:\n\tLibraryWiFi\n\t@thePAD/Magma\n\tHomeNetwork\n"
          allow(model).to receive(:wifi_interface).and_return("en0")
          allow(model).to receive(:run_os_command).and_return(command_result(stdout: networksetup_output))
          
          result = model.preferred_networks
          expect(result).to eq(["@thePAD/Magma", "HomeNetwork", "LibraryWiFi"]) # Sorted alphabetically, case insensitive
        end

        it 'handles empty preferred networks list' do
          allow(model).to receive(:wifi_interface).and_return("en0")
          allow(model).to receive(:run_os_command).and_return(command_result(stdout: "Preferred networks on en0:\n"))
          
          expect(model.preferred_networks).to eq([])
        end
      end

      describe '#_available_network_names' do
        let(:mock_airport_data) do
          {
            "SPAirPortDataType" => [{
              "spairport_airport_interfaces" => [{
                "_name" => "en0",
                "spairport_airport_local_wireless_networks" => [
                  {"_name" => "StrongNetwork", "spairport_signal_noise" => "85/10"},
                  {"_name" => "WeakNetwork", "spairport_signal_noise" => "45/10"},
                  {"_name" => "MediumNetwork", "spairport_signal_noise" => "65/10"}
                ]
              }]
            }]
          }
        end

        it 'returns networks sorted by signal strength descending' do
          allow(model).to receive(:airport_data).and_return(mock_airport_data)
          allow(model).to receive(:wifi_interface).and_return("en0")
          allow(model).to receive(:connected_network_name).and_return(nil)
          
          result = model._available_network_names
          expect(result).to eq(["StrongNetwork", "MediumNetwork", "WeakNetwork"])
        end

        it 'uses different data key when connected to network' do
          connected_data = JSON.parse(mock_airport_data.to_json)
          connected_data["SPAirPortDataType"][0]["spairport_airport_interfaces"][0]["spairport_airport_other_local_wireless_networks"] = [
            {"_name" => "OtherNetwork", "spairport_signal_noise" => "75/10"}
          ]
          
          allow(model).to receive(:airport_data).and_return(connected_data)
          allow(model).to receive(:wifi_interface).and_return("en0") 
          allow(model).to receive(:connected_network_name).and_return("CurrentNetwork")
          
          result = model._available_network_names
          expect(result).to eq(["OtherNetwork"])
        end

        it 'removes duplicate network names' do
          duplicate_data = {
            "SPAirPortDataType" => [{
              "spairport_airport_interfaces" => [{
                "_name" => "en0",
                "spairport_airport_local_wireless_networks" => [
                  {"_name" => "DupeNetwork", "spairport_signal_noise" => "85/10"},
                  {"_name" => "DupeNetwork", "spairport_signal_noise" => "45/10"},
                  {"_name" => "UniqueNetwork", "spairport_signal_noise" => "65/10"}
                ]
              }]
            }]
          }
          
          allow(model).to receive(:airport_data).and_return(duplicate_data)
          allow(model).to receive(:wifi_interface).and_return("en0")
          allow(model).to receive(:connected_network_name).and_return(nil)
          
          result = model._available_network_names
          expect(result).to eq(["DupeNetwork", "UniqueNetwork"])
        end
      end

      describe '#airport_data (private)' do
        it 'parses system_profiler JSON output' do
          json_output = '{"SPAirPortDataType": [{"test": "data"}]}'
          allow(model).to receive(:run_os_command).with(%w[system_profiler -json SPAirPortDataType]).and_return(command_result(stdout: json_output))
          
          result = model.send(:airport_data)
          expect(result).to eq({"SPAirPortDataType" => [{"test" => "data"}]})
        end

        it 'raises error for invalid JSON' do
          allow(model).to receive(:run_os_command).and_return(command_result(stdout: "invalid json"))
          
          expect { model.send(:airport_data) }.to raise_error(/Failed to parse system_profiler output/)
        end
      end

      describe '#run_swift_command' do
        it 'constructs and executes swift command with arguments' do
          expect(model).to receive(:run_os_command) do |cmd|
            expect(cmd[0]).to eq("swift")
            expect(cmd[1]).to end_with("WifiNetworkConnector.swift")
            expect(cmd[2]).to eq("TestNetwork")
            expect(cmd[3]).to eq("password123")
          end
          
          model.run_swift_command("WifiNetworkConnector", "TestNetwork", "password123")
        end

        it 'handles commands with no arguments' do
          expect(model).to receive(:run_os_command) do |cmd|
            expect(cmd[0]).to eq("swift")
            expect(cmd[1]).to end_with("WifiNetworkDisconnector.swift")
            expect(cmd.length).to eq(2)
          end
          
          model.run_swift_command("WifiNetworkDisconnector")
        end
      end

      describe '#_connect method branching' do
        it 'uses Swift method when CoreWLAN is available' do
          allow(model).to receive(:swift_and_corewlan_present?).and_return(true)
          expect(model).to receive(:os_level_connect_using_swift).with("TestNetwork", "password")
          expect(model).not_to receive(:os_level_connect_using_networksetup)
          
          model._connect("TestNetwork", "password")
        end

        it 'uses networksetup method when CoreWLAN is not available' do
          allow(model).to receive(:swift_and_corewlan_present?).and_return(false)
          expect(model).to receive(:os_level_connect_using_networksetup).with("TestNetwork", "password")
          expect(model).not_to receive(:os_level_connect_using_swift)
          
          model._connect("TestNetwork", "password")
        end

        it 'handles connection without password' do
          allow(model).to receive(:swift_and_corewlan_present?).and_return(true)
          expect(model).to receive(:os_level_connect_using_swift).with("TestNetwork", nil)
          
          model._connect("TestNetwork")
        end
      end

      describe '#os_level_connect_using_networksetup' do
        it 'constructs networksetup command with password' do
          allow(model).to receive(:wifi_interface).and_return("en0")
          expect(model).to receive(:run_os_command)
            .with(["networksetup", "-setairportnetwork", "en0", "TestNetwork", "password123"])
            .and_return(success_result)

          model.os_level_connect_using_networksetup("TestNetwork", "password123")
        end

        it 'constructs networksetup command without password' do
          allow(model).to receive(:wifi_interface).and_return("en0")
          expect(model).to receive(:run_os_command)
            .with(["networksetup", "-setairportnetwork", "en0", "TestNetwork"])
            .and_return(success_result)

          model.os_level_connect_using_networksetup("TestNetwork")
        end

        it 'raises NetworkAuthenticationError with reason when password is invalid' do
          allow(model).to receive(:wifi_interface).and_return("en0")
          failure_output = "Failed to join network TestNetwork.\nReason: Invalid password."
          allow(model).to receive(:run_os_command)
            .with(["networksetup", "-setairportnetwork", "en0", "TestNetwork", "badpass"])
            .and_return(command_result(stdout: failure_output))

          expect do
            model.os_level_connect_using_networksetup("TestNetwork", "badpass")
          end.to raise_error(WifiWand::NetworkAuthenticationError) do |error|
            expect(error.reason).to eq("Reason: Invalid password.")
            expect(error.message).to include("Invalid password")
          end
        end
      end

      describe '#os_level_connect_using_swift' do
        it 'passes network and password to Swift command' do
          expect(model).to receive(:run_swift_command).with('WifiNetworkConnector', 'TestNetwork', 'password123')
          
          model.os_level_connect_using_swift("TestNetwork", "password123")
        end

        it 'passes only network name when no password provided' do
          expect(model).to receive(:run_swift_command).with('WifiNetworkConnector', 'TestNetwork')
          
          model.os_level_connect_using_swift("TestNetwork")
        end
      end

      describe '#connection_security_type' do
        let(:network_name) { 'TestNetwork' }
        let(:wifi_interface) { 'en0' }
        
        before(:each) do
          allow(model).to receive(:_connected_network_name).and_return(network_name)
          allow(model).to receive(:wifi_interface).and_return(wifi_interface)
        end

        [
          ['WPA2', 'WPA2'],
          ['WPA3', 'WPA3'], 
          ['WPA', 'WPA'],
          ['WPA1', 'WPA'],
          ['WEP', 'WEP'],
          ['Unknown Security', nil]
        ].each do |security_mode, expected_result|
          it "returns #{expected_result || 'nil'} for #{security_mode}" do
            airport_data = {
              'SPAirPortDataType' => [{
                'spairport_airport_interfaces' => [{
                  '_name' => wifi_interface,
                  'spairport_airport_local_wireless_networks' => [{
                    '_name' => network_name,
                    'spairport_security_mode' => security_mode
                  }]
                }]
              }]
            }
            
            allow(model).to receive(:airport_data).and_return(airport_data)
            
            expect(model.connection_security_type).to eq(expected_result)
          end
        end

        it 'returns nil when not connected to any network' do
          allow(model).to receive(:_connected_network_name).and_return(nil)
          
          expect(model.connection_security_type).to be_nil
        end

        it 'returns nil when airport data is unavailable' do
          allow(model).to receive(:airport_data).and_return({})
          
          expect(model.connection_security_type).to be_nil
        end

        it 'returns nil when wifi interface not found in airport data' do
          airport_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name' => 'other_interface',
                'spairport_airport_local_wireless_networks' => []
              }]
            }]
          }
          
          allow(model).to receive(:airport_data).and_return(airport_data)
          
          expect(model.connection_security_type).to be_nil
        end

        it 'returns nil when connected network not found in scan results' do
          airport_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name' => wifi_interface,
                'spairport_airport_local_wireless_networks' => [{
                  '_name' => 'OtherNetwork',
                  'spairport_security_mode' => 'WPA2'
                }]
              }]
            }]
          }
          
          allow(model).to receive(:airport_data).and_return(airport_data)
          
          expect(model.connection_security_type).to be_nil
        end

        it 'returns nil when security mode information is missing' do
          airport_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name' => wifi_interface,
                'spairport_airport_local_wireless_networks' => [{
                  '_name' => network_name
                  # No spairport_security_mode key
                }]
              }]
            }]
          }
          
          allow(model).to receive(:airport_data).and_return(airport_data)
          
          expect(model.connection_security_type).to be_nil
        end
      end

      describe '#detect_wifi_service_name edge cases' do
        it 'returns Wi-Fi as final fallback when all detection fails' do
          no_wifi_output = "Hardware Port: Ethernet\nDevice: en1"
          allow(model).to receive(:run_os_command).with(%w[networksetup -listallhardwareports]).and_return(command_result(stdout: no_wifi_output))
          allow(model).to receive(:wifi_interface).and_return("en0")
          
          result = model.detect_wifi_service_name
          expect(result).to eq("Wi-Fi")
        end
      end

      describe '#set_nameservers IP validation edge cases' do
        it 'identifies mixed valid and invalid IP addresses' do
          mixed_ips = ["8.8.8.8", "invalid.ip", "1.1.1.1", "999.999.999.999"]
          
          silence_output do
            expect { model.set_nameservers(mixed_ips) }.to raise_error(WifiWand::InvalidIPAddressError) do |error|
              expect(error.invalid_addresses).to include("invalid.ip", "999.999.999.999")
              expect(error.invalid_addresses).not_to include("8.8.8.8", "1.1.1.1")
            end
          end
        end

        it 'handles IP validation exceptions gracefully' do
          # Mock IPAddr to raise exception for specific input
          allow(IPAddr).to receive(:new).with("problematic.ip").and_raise(StandardError.new("Parse error"))
          allow(IPAddr).to receive(:new).with("8.8.8.8").and_return(double(ipv4?: true))
          
          problematic_ips = ["8.8.8.8", "problematic.ip"]
          silence_output do
            expect { model.set_nameservers(problematic_ips) }.to raise_error(WifiWand::InvalidIPAddressError)
          end
        end
      end
    end
  end
end
