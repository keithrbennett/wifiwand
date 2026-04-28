# frozen_string_literal: true

require 'json'
require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/models/mac_os_model'

module WifiWand
  describe MacOsModel do
    # Prevent accidental Keychain UI prompts in all tests (both real-env and mocked)
    before do
      unless uses_real_env? || RSpec.current_example&.metadata&.[](:keychain_integration)
        # Avoid macOS Keychain prompts during mocked tests
        allow_any_instance_of(described_class).to receive(:preferred_network_password).and_return(nil)
        # Ensure initialization doesn’t fail due to interface detection during mocked tests
        allow_any_instance_of(described_class).to receive(:probe_wifi_interface).and_return('en0')

        allow_any_instance_of(WifiWand::NetworkConnectivityTester).to receive(:internet_connectivity_state)
          .and_return(:reachable)
        allow_any_instance_of(WifiWand::NetworkConnectivityTester).to receive(:tcp_connectivity?)
          .and_return(true)
        allow_any_instance_of(WifiWand::NetworkConnectivityTester).to receive(:dns_working?)
          .and_return(true)

      end
    end

    describe 'version support' do
      subject(:model) { create_mac_os_test_model }

      describe '#detect_macos_version' do
        it 'detects macOS version when command succeeds' do
          model = create_mac_os_test_model
          allow(model).to receive(:run_command_using_args).with(%w[sw_vers -productVersion])
            .and_return(command_result(stdout: "15.6\n"))
          expect(model.send(:detect_macos_version)).to eq('15.6')
        end

        it 'returns nil when command fails' do
          model = create_mac_os_test_model
          allow(model).to receive(:run_command_using_args).with(%w[sw_vers -productVersion])
            .and_raise(StandardError.new('Command failed'))
          expect { model.send(:detect_macos_version) }.not_to raise_error
          expect(model.send(:detect_macos_version)).to be_nil
        end
      end

      # Network connection tests (highest risk)
      context 'when running network connection operations',
        :real_env_read_write, real_env_os: :os_mac do
        subject { create_mac_os_test_model }

        describe '#_connect' do
          it 'raises error for non-existent network' do
            # Swift command exits with status 1 and "Error: Network not found" message
            expect { subject._connect('non_existent_network_123') }
              .to raise_error(WifiWand::CommandExecutor::OsCommandError)
          end
        end
      end

      context 'when running read-only real-environment inspections',
        :real_env_read_only, real_env_os: :os_mac do
        subject { create_mac_os_test_model }

        describe '#set_nameservers' do
          it 'validates IP address format before setting' do
            invalid_scenarios = [
              ['invalid.ip.address'],
              ['999.999.999.999'],
              ['not.an.ip', '8.8.8.8'],
              ['192.168.1.1', 'bad.ip'],
            ]

            invalid_scenarios.each do |invalid_nameservers|
              expect { subject.set_nameservers(invalid_nameservers) }
                .to raise_error(WifiWand::InvalidIPAddressError),
                  "Should reject invalid nameservers: #{invalid_nameservers}"
            end
          end
        end

        describe 'interface detection consistency' do
          it 'consistently detects same WiFi interface across calls' do
            first_interface = subject.wifi_interface
            expect(first_interface).not_to be_nil
            expect(first_interface).to match(/^en\d+$/)

            2.times do
              expect(subject.wifi_interface).to eq(first_interface)
            end
          end

          it 'detects WiFi service name consistently' do
            first_service = subject.detect_wifi_service_name
            expect(first_service).not_to be_nil

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
            else
              skip 'macOS version detection failed'
            end
          end
        end
      end
    end

    # Mocked tests for core functionality
    context 'when testing core functionality' do
      subject(:model) { create_mac_os_test_model }
      let(:success_result) do
        WifiWand::CommandExecutor::OsCommandResult.new(
          stdout: '', stderr: '', combined_output: '', exitstatus: 0, command: '', duration: 0.1
        )
      end

      describe '#os_id' do
        it 'returns mac symbol' do
          expect(described_class.os_id).to eq(:mac)
        end
      end

      describe '#detect_wifi_service_name' do
        let(:networksetup_output) do
          "Hardware Port: Ethernet\nDevice: en1\nEthernet Address: aa:bb:cc:dd:ee:ff\n\n" \
            "Hardware Port: Wi-Fi\nDevice: en0\nEthernet Address: ac:bc:32:b9:a9:9d"
        end

        it 'detects common WiFi service patterns' do
          test_cases = [
            ["Hardware Port: Wi-Fi\nDevice: en0", 'Wi-Fi'],
            ["Hardware Port: AirPort\nDevice: en0", 'AirPort'],
            ["Hardware Port: Wireless\nDevice: en0", 'Wireless'],
            ["Hardware Port: WiFi\nDevice: en0", 'WiFi'],
            ["Hardware Port: WLAN\nDevice: en0", 'WLAN'],
          ]

          test_cases.each do |output, expected|
            # Clear any cached value and mock the command
            model.instance_variable_set(:@detect_wifi_service_name, nil)
            allow(model).to receive(:run_command_using_args).with(%w[networksetup -listallhardwareports])
              .and_return(command_result(stdout: output))
            expect(model.detect_wifi_service_name).to eq(expected)
          end
        end

        it 'falls back to Wi-Fi when no pattern matches' do
          no_wifi_output = "Hardware Port: Ethernet\nDevice: en1"
          allow(model).to receive(:run_command_using_args).with(%w[networksetup -listallhardwareports])
            .and_return(command_result(stdout: no_wifi_output))
          allow(model).to receive(:wifi_interface).and_return('en0')
          expect(model.detect_wifi_service_name).to eq('Wi-Fi')
        end

        it 'derives service name from previous Hardware Port line for detected interface' do
          # Ensure cache does not interfere
          model.instance_variable_set(:@detect_wifi_service_name, nil)
          output = "Hardware Port: SpecialWifi\nDevice: en0\nEthernet Address: aa:bb:cc:dd:ee:ff\n\n" \
            "Hardware Port: Ethernet\nDevice: en1\n"
          allow(model).to receive(:run_command_using_args).with(%w[networksetup -listallhardwareports])
            .and_return(command_result(stdout: output))
          allow(model).to receive(:wifi_interface).and_return('en0')
          expect(model.detect_wifi_service_name).to eq('SpecialWifi')
        end
      end

      describe '#is_wifi_interface?' do
        it 'returns true when networksetup confirms the interface is WiFi' do
          allow(model).to receive(:run_command_using_args)
            .with(%w[networksetup -listpreferredwirelessnetworks en0])
            .and_return(command_result(stdout: ''))

          expect(model.is_wifi_interface?('en0')).to be(true)
        end

        it 'returns false when networksetup reports a non-WiFi interface' do
          error = os_command_error(exitstatus: 10, command: 'networksetup', text: '')
          allow(model).to receive(:run_command_using_args)
            .with(%w[networksetup -listpreferredwirelessnetworks en1])
            .and_raise(error)

          expect(model.is_wifi_interface?('en1')).to be(false)
        end

        it 're-raises unexpected networksetup failures' do
          error = os_command_error(exitstatus: 5, command: 'networksetup', text: 'unexpected failure')
          allow(model).to receive(:run_command_using_args)
            .with(%w[networksetup -listpreferredwirelessnetworks en2])
            .and_raise(error)

          expect { model.is_wifi_interface?('en2') }
            .to raise_error(WifiWand::CommandExecutor::OsCommandError, /unexpected failure/)
        end
      end

      describe '#detect_wifi_interface_using_networksetup' do
        it 'extracts WiFi interface from networksetup output' do
          output = "Hardware Port: Wi-Fi\nDevice: en0\nEthernet Address: aa:bb:cc\n\n" \
            "Hardware Port: Ethernet\nDevice: en1\n"
          allow(model).to receive(:run_command_using_args).with(%w[networksetup -listallhardwareports])
            .and_return(command_result(stdout: output))
          # Also exercise dynamic service name path
          allow(model).to receive(:detect_wifi_service_name).and_call_original
          expect(model.detect_wifi_interface_using_networksetup).to eq('en0')
        end

        it 'raises WifiInterfaceError when WiFi service not found' do
          output = "Hardware Port: Ethernet\nDevice: en1\n"
          allow(model).to receive(:run_command_using_args).with(%w[networksetup -listallhardwareports])
            .and_return(command_result(stdout: output))
          allow(model).to receive(:detect_wifi_service_name).and_return('Wi-Fi')
          expect do
            model.detect_wifi_interface_using_networksetup
          end.to raise_error(WifiWand::WifiInterfaceError)
        end
      end



      describe '#_ip_address' do
        it 'handles different ipconfig responses' do
          test_cases = [
            ["192.168.1.100\n", '192.168.1.100'],  # Valid IP
            ['10.0.0.5', '10.0.0.5'],              # No newline
            [os_command_error(exitstatus: 1, command: 'ipconfig', text: ''), nil], # Interface down
          ]

          test_cases.each do |response, expected|
            if response.is_a?(Exception)
              allow(model).to receive(:run_command_using_args).and_raise(response)
            else
              allow(model).to receive(:run_command_using_args).and_return(command_result(stdout: response))
            end

            expect(model._ip_address).to eq(expected)
          end
        end

        it 're-raises unexpected ipconfig errors' do
          allow(model).to receive(:wifi_interface).and_return('en0')
          allow(model).to receive(:run_command_using_args).and_raise(
            os_command_error(exitstatus: 2, command: 'ipconfig', text: 'boom')
          )
          expect { model._ip_address }.to raise_error(WifiWand::CommandExecutor::OsCommandError)
        end
      end

      describe '#_connected_network_name' do
        let(:helper_double) do
          instance_double(WifiWand::MacOsWifiAuthHelper::Client)
        end

        before do
          model.instance_variable_set(:@mac_helper_client, nil)
          allow(WifiWand::MacOsWifiAuthHelper::Client).to receive(:new).and_return(helper_double)
        end

        it 'returns the helper-provided SSID when available' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(payload: 'HelperSSID')
          allow(helper_double).to receive(:connected_network_name).and_return(result)

          expect(model._connected_network_name).to eq('HelperSSID')
        end

        it 'falls back to airport data when helper returns nil' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(airport_data: { 'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                 => 'en0',
              'spairport_current_network_information' => { '_name' => 'ProfilerNet' },
            }],
          }] }, wifi_interface: 'en0')

          expect(model._connected_network_name).to eq('ProfilerNet')
        end

        it 'returns nil when helper returns nil and airport data is missing current network information' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(airport_data: { 'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                 => 'en0',
              'spairport_current_network_information' => nil,
            }],
          }] }, wifi_interface: 'en0')

          expect(model._connected_network_name).to be_nil
        end

        it 'falls back to airport data when helper is blocked by Location Services' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(
            location_services_blocked: true,
            error_message:             'Location Services denied'
          )
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(airport_data: { 'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                 => 'en0',
              'spairport_current_network_information' => { '_name' => 'ProfilerNet' },
            }],
          }] }, wifi_interface: 'en0')

          expect(model._connected_network_name).to eq('ProfilerNet')
        end

        it 'refreshes connected network state across separate public read operations' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(payload: nil)
          first_airport_data = JSON.generate(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => { '_name' => 'ProfilerNetA' },
              }],
            }]
          )
          second_airport_data = JSON.generate(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => { '_name' => 'ProfilerNetB' },
              }],
            }]
          )

          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(wifi_interface: 'en0', wifi_on?: true)
          expect(model).to receive(:run_command_using_args).with(
            %w[system_profiler -json SPAirPortDataType],
            true,
            timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
          ).twice.and_return(
            command_result(stdout: first_airport_data),
            command_result(stdout: second_airport_data)
          )

          expect(model.connected_network_name).to eq('ProfilerNetA')
          expect(model.connected_network_name).to eq('ProfilerNetB')
        end

        it 'raises a targeted exact-identity error when macOS redacts the current SSID' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(
            payload:                   nil,
            location_services_blocked: true,
            error_message:             'Location Services denied'
          )
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(
            wifi_on?:       true,
            connected?:     true,
            airport_data:   { 'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => { '_name' => nil },
              }],
            }] },
            wifi_interface: 'en0'
          )

          expect { model.connected_network_name }.to raise_error(
            WifiWand::MacOsRedactionError,
            /Exact WiFi network identity.*wifi-wand-macos-setup.*wifiwand-helper/
          )
        end
      end

      describe '#associated?' do
        let(:helper_double) do
          instance_double(WifiWand::MacOsWifiAuthHelper::Client)
        end

        before do
          model.instance_variable_set(:@mac_helper_client, nil)
          allow(WifiWand::MacOsWifiAuthHelper::Client).to receive(:new).and_return(helper_double)
          allow(model).to receive_messages(wifi_on?: true, wifi_interface: 'en0')
        end

        it 'returns true when the helper provides a real SSID' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(payload: 'MyNetwork')
          allow(helper_double).to receive(:connected_network_name).and_return(result)

          expect(model).not_to receive(:airport_data)
          expect(model.associated?).to be(true)
        end

        it 'returns true when airport data shows non-empty current network information ' \
          'without an SSID name' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive(:airport_data).and_return(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => { 'spairport_network_channel' => '6' },
              }],
            }]
          )

          expect(model.associated?).to be(true)
        end

        it 'returns false when airport data only has an empty current-network hash' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive(:airport_data).and_return(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => {},
              }],
            }]
          )

          expect(model.associated?).to be(false)
        end

        it 'returns false when the helper reports no SSID and airport data has no current network info' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive(:airport_data).and_return(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{ '_name' => 'en0' }],
            }]
          )

          expect(model.associated?).to be(false)
        end
      end

      describe '#connected?' do
        let(:helper_double) do
          instance_double(WifiWand::MacOsWifiAuthHelper::Client)
        end

        before do
          model.instance_variable_set(:@mac_helper_client, nil)
          allow(WifiWand::MacOsWifiAuthHelper::Client).to receive(:new).and_return(helper_double)
          allow(model).to receive(:wifi_on?).and_return(true)
        end

        it 'returns true when the helper provides a real SSID (Sonoma redaction case)' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(payload: 'MyNetwork')
          allow(helper_double).to receive(:connected_network_name).and_return(result)

          expect(model).not_to receive(:airport_data)
          expect(model.connected?).to be(true)
        end

        it 'returns false when wifi is off, without consulting the helper' do
          allow(model).to receive(:wifi_on?).and_return(false)

          expect(helper_double).not_to receive(:connected_network_name)
          expect(model.connected?).to be(false)
        end

        it 'falls back to system_profiler when helper returns nil' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(
            airport_data:   { 'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => { '_name' => 'SomeNet' },
              }],
            }] },
            wifi_interface: 'en0'
          )

          expect(model.connected?).to be(true)
        end

        it 'returns false when helper returns nil and system_profiler lacks current-network info' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(
            airport_data:      { 'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name' => 'en0',
              }],
            }] },
            wifi_interface:    'en0',
            default_interface: nil,
            _ip_address:       nil
          )

          expect(model.connected?).to be(false)
        end

        it 'does not treat a placeholder SSID from the helper as connected' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(payload: '<redacted>')
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(
            airport_data:      { 'SPAirPortDataType' => [{ 'spairport_airport_interfaces' => [] }] },
            wifi_interface:    'en0',
            default_interface: nil,
            _ip_address:       nil
          )

          expect(model.connected?).to be(false)
        end

        it 'returns true when association evidence exists but SSID is redacted' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(
            location_services_blocked: true,
            error_message:             'Location Services denied'
          )
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(
            airport_data:      { 'SPAirPortDataType' => [{ 'spairport_airport_interfaces' => [{
              '_name' => 'en0',
            }] }] },
            wifi_interface:    'en0',
            default_interface: 'en0'
          )
          allow(model).to receive(:_ip_address).and_return(nil)

          expect(model.connected?).to be(true)
        end

        it 'returns true when the helper is disabled and the WiFi interface still has an IP address' do
          model.instance_variable_set(:@mac_helper_client, nil)
          allow(WifiWand::MacOsWifiAuthHelper::Client).to receive(:new).and_call_original
          allow(model).to receive_messages(
            airport_data:      { 'SPAirPortDataType' => [{ 'spairport_airport_interfaces' => [{
              '_name' => 'en0',
            }] }] },
            wifi_interface:    'en0',
            default_interface: nil,
            _ip_address:       '192.168.1.44'
          )

          original_env = ENV['WIFIWAND_DISABLE_MAC_HELPER']
          ENV['WIFIWAND_DISABLE_MAC_HELPER'] = '1'
          begin
            expect_any_instance_of(WifiWand::MacOsWifiAuthHelper::Client)
              .not_to receive(:ensure_helper_installed)
            expect(model.connected?).to be(true)
          ensure
            ENV['WIFIWAND_DISABLE_MAC_HELPER'] = original_env
          end
        end
      end

      describe 'Sonoma SSID redaction: helper succeeds but system_profiler lacks current-network data' do
        let(:helper_double) { instance_double(WifiWand::MacOsWifiAuthHelper::Client) }
        let(:airport_data_without_current_network) do
          { 'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{ '_name' => 'en0' }],
          }] }
        end

        before do
          model.instance_variable_set(:@mac_helper_client, nil)
          allow(WifiWand::MacOsWifiAuthHelper::Client).to receive(:new).and_return(helper_double)
          allow(model).to receive_messages(
            wifi_on?:       true,
            wifi_interface: 'en0',
            airport_data:   airport_data_without_current_network
          )
          # Helper returns real SSID; system_profiler has no current-network key
          helper_ssid_result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(payload: 'SonomaNet')
          allow(helper_double).to receive(:connected_network_name).and_return(helper_ssid_result)
        end

        it 'connected? returns true' do
          expect(model.connected?).to be(true)
        end

        it 'connection_ready? succeeds when the network name matches' do
          expect(model.connection_ready?('SonomaNet')).to be(true)
        end

        it 'ip_address does not raise and delegates to _ip_address' do
          allow(model).to receive(:_ip_address).and_return('10.0.0.42')
          expect(model.ip_address).to eq('10.0.0.42')
        end
      end

      describe '#nameservers_using_networksetup' do
        it 'parses networksetup DNS output correctly' do
          test_cases = [
            ["8.8.8.8\n1.1.1.1\n", ['8.8.8.8', '1.1.1.1']],
            ["There aren't any DNS Servers set on Wi-Fi.\n", []],
            ['192.168.1.1', ['192.168.1.1']],
          ]

          test_cases.each do |output, expected|
            allow(model).to receive_messages(
              detect_wifi_service_name: 'Wi-Fi',
              run_command_using_args:   command_result(stdout: output)
            )
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

          allow(model).to receive(:run_command_using_args).with(%w[scutil --dns])
            .and_return(command_result(stdout: scutil_output))
          result = model.nameservers_using_scutil
          expect(result).to contain_exactly('8.8.8.8', '1.1.1.1', '9.9.9.9')
        end
      end

      describe '#set_nameservers' do
        it 'handles different nameserver configurations' do
          test_cases = [
            { input: ['8.8.8.8', '1.1.1.1'], expected_args: ['8.8.8.8', '1.1.1.1'] },
            { input: ['192.168.1.1'], expected_args: ['192.168.1.1'] },
            { input: :clear, expected_args: ['empty'] },
          ]

          test_cases.each do |tc|
            allow(model).to receive(:detect_wifi_service_name).and_return('Wi-Fi')
            if tc[:input] == :clear
              expect(model).to receive(:run_command_using_args)
                .with(['networksetup', '-setdnsservers', 'Wi-Fi', 'empty'])
            else
              expect(model).to receive(:run_command_using_args).with(['networksetup', '-setdnsservers',
                'Wi-Fi'] + tc[:input])
            end
            expect(model.set_nameservers(tc[:input])).to eq(tc[:input])
          end
        end

        it 'accepts IPv6 DNS addresses' do
          ipv6_test_cases = [
            { input:         ['2606:4700:4700::1111', '2606:4700:4700::1001'],
              expected_args: ['2606:4700:4700::1111', '2606:4700:4700::1001'] },
            { input:         ['2001:4860:4860::8888'],
              expected_args: ['2001:4860:4860::8888'] },
            { input:         ['8.8.8.8', '2606:4700:4700::1111'],
              expected_args: ['8.8.8.8', '2606:4700:4700::1111'] },
          ]

          ipv6_test_cases.each do |tc|
            allow(model).to receive(:detect_wifi_service_name).and_return('Wi-Fi')
            expect(model).to receive(:run_command_using_args).with(['networksetup', '-setdnsservers',
              'Wi-Fi'] + tc[:input])
            expect(model.set_nameservers(tc[:input])).to eq(tc[:input])
          end
        end

        it 'validates IP addresses and raises error for invalid ones' do
          allow(model).to receive(:detect_wifi_service_name).and_return('Wi-Fi')
          invalid_nameservers = ['8.8.8.8', 'invalid.ip', '2001:db8:::1']
          silence_output do
            expect { model.set_nameservers(invalid_nameservers) }
              .to raise_error(WifiWand::InvalidIPAddressError) do |error|
                expect(error.invalid_addresses).to contain_exactly('invalid.ip', '2001:db8:::1')
              end
          end
        end

        it 'treats nil nameserver input as invalid' do
          allow(model).to receive(:detect_wifi_service_name).and_return('Wi-Fi')
          invalid_nameservers = ['8.8.8.8', nil]

          silence_output do
            expect { model.set_nameservers(invalid_nameservers) }
              .to raise_error(WifiWand::InvalidIPAddressError) do |error|
                expect(error.invalid_addresses).to eq([nil])
              end
          end
        end

        it 'treats non-string nameserver input as invalid' do
          allow(model).to receive(:detect_wifi_service_name).and_return('Wi-Fi')
          invalid_nameservers = ['8.8.8.8', 123]

          silence_output do
            expect { model.set_nameservers(invalid_nameservers) }
              .to raise_error(WifiWand::InvalidIPAddressError) do |error|
                expect(error.invalid_addresses).to eq([123])
              end
          end
        end
      end

      describe '#default_interface' do
        it 'extracts default interface from route output' do
          test_cases = [
            ["   interface: en0\n", 'en0'],
            ['   interface: wlan0', 'wlan0'],
            ['', nil],
            [os_command_error(exitstatus: 1, command: 'route', text: ''), nil],
          ]

          test_cases.each do |response, expected|
            if response.is_a?(Exception)
              allow(model).to receive(:run_command_using_args).with(%w[route -n get default],
                false).and_raise(response)
            else
              allow(model).to receive(:run_command_using_args).with(%w[route -n get default],
                false).and_return(command_result(stdout: response))
            end

            expect(model.default_interface).to eq(expected)
          end
        end
      end

      describe '#mac_address' do
        it 'extracts MAC address from ifconfig output' do
          ifconfig_output = "en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500\n" \
            "\tether ac:bc:32:b9:a9:9d\n"
          allow(model).to receive(:wifi_interface).and_return('en0')
          allow(model).to receive(:run_command_using_args).with(%w[ifconfig en0])
            .and_return(command_result(stdout: ifconfig_output))
          expect(model.mac_address).to eq('ac:bc:32:b9:a9:9d')
        end
      end

      describe '#remove_preferred_network' do
        it 'constructs a correctly escaped removal command for various network names' do
          allow(model).to receive(:wifi_interface).and_return('en0')

          test_cases = [
            [
              'Simple',
              %w[sudo networksetup -removepreferredwirelessnetwork en0 Simple],
            ],
            [
              'Network With Spaces',
              ['sudo', 'networksetup', '-removepreferredwirelessnetwork', 'en0', 'Network With Spaces'],
            ],
            [
              'Network"WithQuotes',
              ['sudo', 'networksetup', '-removepreferredwirelessnetwork', 'en0', 'Network"WithQuotes'],
            ],
            [
              "Network'WithSingleQuotes",
              ['sudo', 'networksetup', '-removepreferredwirelessnetwork', 'en0', "Network'WithSingleQuotes"],
            ],
          ]

          test_cases.each do |network_name, expected_command_array|
            expect(model).to receive(:run_command_using_args).with(
              expected_command_array,
              true,
              timeout_in_secs: described_class::SUDO_NETWORKSETUP_TIMEOUT_SECONDS
            )
            expect(model.remove_preferred_network(network_name)).to eq([network_name])
          end
        end
      end

      describe '#open_resource' do
        it 'constructs open commands properly' do
          test_cases = [
            'http://example.com',
            'file:///path with spaces/file.txt',
            '/Applications/Safari.app',
          ]

          test_cases.each do |resource|
            expect(model).to receive(:run_command_using_args) do |cmd_array|
              expect(cmd_array[0]).to eq('open')
              expect(cmd_array[1]).to eq(resource)
            end
            model.open_resource(resource)
          end
        end
      end

      describe '#probe_wifi_interface' do
        # Restore original method behavior for these specific tests
        before do
          allow_any_instance_of(described_class).to receive(:probe_wifi_interface).and_call_original
          # Force fallback path to system_profiler for deterministic tests
          allow_any_instance_of(described_class).to receive(:detect_wifi_interface_using_networksetup)
            .and_return(nil)
        end

        # Provide a valid interface during initialization to avoid init failures in this block
        subject(:model) { create_mac_os_test_model(wifi_interface: 'en0') }
        let(:system_profiler_output) do
          {
            'SPNetworkDataType' => [
              { '_name' => 'Ethernet', 'interface' => 'en1' },
              { '_name' => 'Wi-Fi', 'interface' => 'en0' },
              { '_name' => 'Bluetooth PAN', 'interface' => 'en3' },
            ],
          }.to_json
        end

        it 'detects WiFi interface from system_profiler' do
          expect(model).to receive(:run_command_using_args).with(
            %w[system_profiler -json SPNetworkDataType],
            true,
            timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
          ).and_return(command_result(stdout: system_profiler_output))

          expect(model.probe_wifi_interface).to eq('en0')
        end

        it 'returns nil when WiFi service not found' do
          allow(model).to receive(:run_command_using_args)
            .and_return(command_result(stdout: '{"SPNetworkDataType": []}'))
          expect(model.probe_wifi_interface).to be_nil
        end

        it 'handles JSON parse errors gracefully' do
          allow(model).to receive(:run_command_using_args).and_return(command_result(stdout: 'invalid json'))
          expect { model.probe_wifi_interface }.to raise_error(JSON::ParserError)
        end

        it 'uses system_profiler fallback without re-entering networksetup after failure' do
          allow(model).to receive(:detect_wifi_interface_using_networksetup).and_raise(StandardError, 'boom')
          allow(model).to receive(:detect_wifi_service_name).and_raise('should not be called')
          allow(model).to receive(:run_command_using_args)
            .and_return(command_result(stdout: system_profiler_output))

          expect(model.probe_wifi_interface).to eq('en0')
        end
      end

      describe '#_preferred_network_password' do
        it 'handles different keychain scenarios' do
          test_cases = [
            [os_command_error(exitstatus: 44, command: 'security', text: ''), nil], # Not found
            [
              os_command_error(exitstatus: 45, command: 'security', text: ''),
              WifiWand::KeychainAccessDeniedError,
            ],
            [
              os_command_error(exitstatus: 128, command: 'security', text: ''),
              WifiWand::KeychainAccessCancelledError,
            ],
            [
              os_command_error(exitstatus: 51, command: 'security', text: ''),
              WifiWand::KeychainNonInteractiveError,
            ],
            [os_command_error(exitstatus: 25, command: 'security', text: ''), WifiWand::KeychainError],
            [os_command_error(exitstatus: 1, command: 'security', text: 'could not be found'), nil],
            [
              os_command_error(exitstatus: 1, command: 'security', text: 'other error'),
              WifiWand::KeychainError,
            ],
            %w[mypassword123 mypassword123],
          ]

          test_cases.each do |response, expected|
            if response.is_a?(Exception)
              allow(model).to receive(:run_command_using_args).and_raise(response)
            else
              allow(model).to receive(:run_command_using_args).and_return(command_result(stdout: response))
            end

            if expected.is_a?(Class) && expected < Exception
              expect { model._preferred_network_password('TestNetwork') }.to raise_error(expected)
            else
              expect(model._preferred_network_password('TestNetwork')).to eq(expected)
            end
          end
        end

        it 'raises detailed KeychainError for unknown exit codes' do
          error = os_command_error(exitstatus: 99, command: 'security', text: 'strange failure')
          allow(model).to receive(:run_command_using_args).and_raise(error)
          expect { model._preferred_network_password('TestNet') }.to raise_error(WifiWand::KeychainError)
        end
      end

      # Runs early to surface any auth prompts before the long suite.
      describe 'preferred_network_password command integration', :keychain_integration do
        it 'invokes security find-generic-password with correct arguments and handles not-found' do
          model = create_mac_os_test_model
          ssid = 'TestNet'

          # Ensure the network is considered preferred so wrapper calls the private method
          allow(model).to receive(:preferred_networks).and_return([ssid])

          expected_cmd = ['security', 'find-generic-password', '-D', 'AirPort network password', '-a', ssid,
            '-w']
          # Expect exact command, but avoid real execution by raising "not found" (exit 44)
          call_sequence = []
          allow(model).to receive(:run_command_using_args) do |command, *args, **kwargs|
            call_sequence << [command, args, kwargs]
            if command == expected_cmd
              expect(args).to eq([true])
              expect(kwargs).to eq(timeout_in_secs: described_class::KEYCHAIN_LOOKUP_TIMEOUT_SECONDS)
              raise os_command_error(exitstatus: 44, command: 'security', text: '')
            else
              command_result(stdout: 'Wi-Fi Power (en0): On')
            end
          end

          expect(model.preferred_network_password(ssid)).to be_nil
          expect(call_sequence.map(&:first)).to include(expected_cmd)
        end

        it 'allows callers to disable the keychain lookup timeout explicitly' do
          model = create_mac_os_test_model
          ssid = 'TestNet'

          allow(model).to receive(:preferred_networks).and_return([ssid])

          expected_cmd = ['security', 'find-generic-password', '-D', 'AirPort network password', '-a', ssid,
            '-w']
          allow(model).to receive(:run_command_using_args) do |command, *args, **kwargs|
            if command == expected_cmd
              expect(args).to eq([true])
              expect(kwargs).to eq(timeout_in_secs: nil)
              raise os_command_error(exitstatus: 44, command: 'security', text: '')
            else
              command_result(stdout: 'Wi-Fi Power (en0): On')
            end
          end

          expect(model.preferred_network_password(ssid, timeout_in_secs: nil)).to be_nil
        end
      end

      describe '#macos_version' do
        it 'handles version detection failure gracefully' do
          # Allow all other commands to execute normally
          allow_any_instance_of(described_class).to receive(:run_command_using_args).and_call_original
          # Cause only the sw_vers call to fail; detection should rescue and set nil
          allow_any_instance_of(described_class)
            .to receive(:run_command_using_args).with(%w[sw_vers -productVersion])
            .and_raise(StandardError.new('Command failed'))
          failing_model = create_mac_os_test_model
          silence_output { expect(failing_model.macos_version).to be_nil }
        end
      end

      describe '#macos_version (real system)', :real_env_read_only, real_env_os: :os_mac do
        # For these real-system checks, allow actual OS command execution
        before do
          allow_any_instance_of(described_class).to receive(:run_command_using_args).and_call_original
        end

        it 'returns a non-empty semantic version on macOS' do
          real_model = create_mac_os_test_model
          v = real_model.macos_version
          expect(v).to match(/^\d+\.\d+(\.\d+)?$/)
        end
      end

      describe '#disconnect' do
        it 'raises when the disconnect command succeeds but association remains' do
          allow(model).to receive_messages(
            wifi_on?:               true,
            associated?:            true,
            connected_network_name: 'TestNet'
          )
          allow(model).to receive(:_disconnect).and_return(nil)
          allow(model).to receive(:till)
            .with(:disassociated, timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT)
            .and_raise(wait_timeout_error(action: :disassociated, timeout: 5))

          expect { model.disconnect }
            .to raise_error(WifiWand::NetworkDisconnectionError, /still associated with 'TestNet'/)
        end

        it 'preserves a useful reason when association remains but no SSID is available' do
          allow(model).to receive_messages(
            wifi_on?:               true,
            associated?:            true,
            connected_network_name: nil
          )
          allow(model).to receive(:_disconnect).and_return(nil)
          allow(model).to receive(:till)
            .with(:disassociated, timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT)
            .and_raise(wait_timeout_error(action: :disassociated, timeout: 5))

          expect { model.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) { |error|
            expect(error.network_name).to be_nil
            expect(error.reason).to eq('interface remained associated')
          }
        end

        it 'raises when disassociation is only transient during verification' do
          allow(model).to receive_messages(
            wifi_on?:                            true,
            connected_network_name:              'TestNet',
            disconnect_stability_window_in_secs: 0.1
          )
          allow(model).to receive(:associated?).and_return(true, false, true)
          allow(model).to receive(:_disconnect).and_return(nil)
          allow(model).to receive(:till)
            .with(:disassociated, timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT)
            .and_return(nil)
          allow(model).to receive(:sleep)

          expect { model.disconnect }
            .to raise_error(WifiWand::NetworkDisconnectionError, /still associated with 'TestNet'/)
        end

        it 'raises when swift fails, ifconfig fallback runs, and the interface remains associated' do
          swift_runtime = instance_double(WifiWand::MacOsSwiftRuntime)
          allow(model).to receive_messages(
            wifi_on?:               true,
            associated?:            true,
            connected_network_name: 'TestNet',
            swift_runtime:          swift_runtime,
            wifi_interface:         'en0'
          )
          allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(true)
          allow(swift_runtime).to receive(:disconnect).and_raise(StandardError, 'swift failure')
          allow(model).to receive(:run_command_using_args).with(
            %w[sudo ifconfig en0 disassociate],
            false,
            timeout_in_secs: WifiWand::MacOsWifiTransport::SUDO_IFCONFIG_TIMEOUT_SECONDS
          ).and_return(command_result(
            stdout:     '',
            stderr:     'sudo denied',
            exitstatus: 1,
            command:    'sudo ifconfig en0 disassociate'
          ))
          allow(model).to receive(:run_command_using_args).with(
            %w[ifconfig en0 disassociate],
            false
          ).and_return(command_result(
            stdout:     '',
            stderr:     '',
            exitstatus: 0,
            command:    'ifconfig en0 disassociate'
          ))
          allow(model).to receive(:till)
            .with(:disassociated, timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT)
            .and_raise(wait_timeout_error(action: :disassociated, timeout: 5))

          expect { model.disconnect }
            .to raise_error(WifiWand::NetworkDisconnectionError, /still associated with 'TestNet'/)
        end

        it 'is a no-op when already disconnected' do
          allow(model).to receive_messages(wifi_on?: true, associated?: false)
          allow(model).to receive(:run_command_using_args)
          allow(model).to receive(:till)
          expect(model).not_to receive(:mac_os_wifi_transport)

          expect(model.disconnect).to be_nil
          expect(model).not_to have_received(:run_command_using_args)
          expect(model).not_to have_received(:till)
        end
      end

      describe '#_disconnect' do
        it 'clears cached airport data before delegating disconnect orchestration' do
          transport = instance_double(WifiWand::MacOsWifiTransport, disconnect: nil)
          allow(model).to receive(:mac_os_wifi_transport).and_return(transport)

          expect(model).to receive(:invalidate_airport_data_cache).ordered
          expect(transport).to receive(:disconnect).ordered

          expect(model._disconnect).to be_nil
        end
      end

      describe '#validate_os_preconditions' do
        it 'returns :ok and emits no warning when Swift/CoreWLAN is available' do
          verbose_model = create_mac_os_test_model(verbose: true, out_stream: StringIO.new)
          expect(verbose_model).to receive(:run_command_using_args).with(
            ['swift', '-e', 'import CoreWLAN'],
            false
          ).and_return(command_result(stdout: ''))

          expect(verbose_model.validate_os_preconditions).to eq(:ok)
          expect(verbose_model.out_stream.string).to eq('')
        end

        it 'returns :ok and emits the runtime warning when Swift is missing' do
          verbose_model = create_mac_os_test_model(verbose: true, out_stream: StringIO.new)
          expect(verbose_model).to receive(:run_command_using_args).with(
            ['swift', '-e', 'import CoreWLAN'],
            false
          ).and_raise(os_command_error(exitstatus: 127, command: 'swift', text: ''))

          expect(verbose_model.validate_os_preconditions).to eq(:ok)
          expect(verbose_model.out_stream.string).to include('Swift command not found (exit code 127)')
        end

        it 'returns :ok and emits the runtime warning when CoreWLAN is unavailable' do
          verbose_model = create_mac_os_test_model(verbose: true, out_stream: StringIO.new)
          expect(verbose_model).to receive(:run_command_using_args).with(
            ['swift', '-e', 'import CoreWLAN'],
            false
          ).and_raise(os_command_error(exitstatus: 1, command: 'swift', text: 'missing framework'))

          expect(verbose_model.validate_os_preconditions).to eq(:ok)
          expect(verbose_model.out_stream.string).to include('CoreWLAN framework not available (exit code 1)')
        end

        it 'returns :ok and emits no warning when verbose is off' do
          quiet_model = create_mac_os_test_model(verbose: false, out_stream: StringIO.new)
          expect(quiet_model).to receive(:run_command_using_args).with(
            ['swift', '-e', 'import CoreWLAN'],
            false
          ).and_raise(os_command_error(exitstatus: 127, command: 'swift', text: ''))

          expect(quiet_model.validate_os_preconditions).to eq(:ok)
          expect(quiet_model.out_stream.string).to eq('')
        end

        it 'delegates the Swift/CoreWLAN probe to the runtime' do
          verbose_model = create_mac_os_test_model(verbose: true, out_stream: StringIO.new)
          expect(verbose_model).to receive(:run_command_using_args).with(
            ['swift', '-e', 'import CoreWLAN'],
            false
          ).and_return(command_result(stdout: ''))

          expect(verbose_model.validate_os_preconditions).to eq(:ok)
        end
      end

      describe '#preferred_networks' do
        it 'parses and sorts preferred networks correctly' do
          networksetup_output = "Preferred networks on en0:\n\tLibraryWiFi\n\t@thePAD/Magma\n\tHomeNetwork\n"
          allow(model).to receive_messages(
            wifi_interface:         'en0',
            run_command_using_args: command_result(stdout: networksetup_output)
          )

          result = model.preferred_networks
          # Sorted alphabetically, case insensitive
          expect(result).to eq(['@thePAD/Magma', 'HomeNetwork', 'LibraryWiFi'])
        end

        it 'handles empty preferred networks list' do
          allow(model).to receive_messages(
            wifi_interface:         'en0',
            run_command_using_args: command_result(stdout: "Preferred networks on en0:\n")
          )

          expect(model.preferred_networks).to eq([])
        end
      end

      describe '#_available_network_names' do
        let(:default_scan_result) do
          WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(payload: [])
        end
        let(:default_connected_result) do
          WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new
        end
        let(:helper_double) do
          instance_double(WifiWand::MacOsWifiAuthHelper::Client)
        end
        let(:mock_airport_data) do
          {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                     => 'en0',
                'spairport_airport_local_wireless_networks' => [
                  { '_name' => 'StrongNetwork', 'spairport_signal_noise' => '85/10' },
                  { '_name' => 'WeakNetwork', 'spairport_signal_noise' => '45/10' },
                  { '_name' => 'MediumNetwork', 'spairport_signal_noise' => '65/10' },
                ],
              }],
            }],
          }
        end

        before do
          model.instance_variable_set(:@mac_helper_client, nil)
          allow(WifiWand::MacOsWifiAuthHelper::Client).to receive(:new).and_return(helper_double)
          allow(helper_double).to receive_messages(
            scan_networks:          default_scan_result,
            connected_network_name: default_connected_result
          )
          allow(model).to receive_messages(mac_helper_client: helper_double, wifi_interface: 'en0')
        end

        it 'returns networks sorted by signal strength descending' do
          allow(model).to receive_messages(
            airport_data:           mock_airport_data,
            wifi_interface:         'en0',
            connected_network_name: nil
          )

          result = model._available_network_names
          expect(result).to eq(%w[StrongNetwork MediumNetwork WeakNetwork])
        end

        it 'uses different data key when connected to network' do
          connected_data = JSON.parse(mock_airport_data.to_json)
          interfaces = connected_data['SPAirPortDataType'][0]['spairport_airport_interfaces'][0]
          interfaces['spairport_airport_other_local_wireless_networks'] =
            [{ '_name' => 'OtherNetwork', 'spairport_signal_noise' => '75/10' }]
          interfaces['spairport_current_network_information'] = { '_name' => 'CurrentNetwork' }

          allow(model).to receive_messages(
            airport_data:           connected_data,
            wifi_interface:         'en0',
            connected_network_name: 'CurrentNetwork'
          )

          result = model._available_network_names
          expect(result).to eq(['OtherNetwork'])
        end

        it 'does not filter out the connected SSID when the macOS scan includes it' do
          connected_data = JSON.parse(mock_airport_data.to_json)
          interfaces = connected_data['SPAirPortDataType'][0]['spairport_airport_interfaces'][0]
          interfaces['spairport_airport_other_local_wireless_networks'] = [
            { '_name' => 'CurrentNetwork', 'spairport_signal_noise' => '92/10' },
            { '_name' => 'OtherNetwork', 'spairport_signal_noise' => '75/10' },
          ]
          interfaces['spairport_current_network_information'] = { '_name' => 'CurrentNetwork' }

          allow(model).to receive_messages(
            airport_data:           connected_data,
            wifi_interface:         'en0',
            connected_network_name: 'CurrentNetwork'
          )

          expect(model._available_network_names).to eq(%w[CurrentNetwork OtherNetwork])
        end

        it 'does not inject the connected SSID when the macOS scan omits it' do
          connected_data = JSON.parse(mock_airport_data.to_json)
          interfaces = connected_data['SPAirPortDataType'][0]['spairport_airport_interfaces'][0]
          interfaces['spairport_airport_other_local_wireless_networks'] = [
            { '_name' => 'OtherNetwork', 'spairport_signal_noise' => '75/10' },
            { '_name' => 'GuestNetwork', 'spairport_signal_noise' => '55/10' },
          ]
          interfaces['spairport_current_network_information'] = { '_name' => 'CurrentNetwork' }

          allow(model).to receive_messages(
            airport_data:           connected_data,
            wifi_interface:         'en0',
            connected_network_name: 'CurrentNetwork'
          )

          expect(model._available_network_names).to eq(%w[OtherNetwork GuestNetwork])
        end

        it 'removes duplicate network names' do
          duplicate_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                     => 'en0',
                'spairport_airport_local_wireless_networks' => [
                  { '_name' => 'DupeNetwork', 'spairport_signal_noise' => '85/10' },
                  { '_name' => 'DupeNetwork', 'spairport_signal_noise' => '45/10' },
                  { '_name' => 'UniqueNetwork', 'spairport_signal_noise' => '65/10' },
                ],
              }],
            }],
          }

          allow(model).to receive_messages(
            airport_data:           duplicate_data,
            wifi_interface:         'en0',
            connected_network_name: nil
          )

          result = model._available_network_names
          expect(result).to eq(%w[DupeNetwork UniqueNetwork])
        end

        it 'filters placeholder network names from helper results' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(
            payload: [
              { 'ssid' => '<hidden>' },
              { 'ssid' => '<redacted>' },
              { 'ssid' => 'VisibleNetwork' },
            ]
          )
          allow(helper_double).to receive(:scan_networks).and_return(result)

          result = model._available_network_names
          expect(result).to eq(['VisibleNetwork'])
        end

        it 'filters placeholder network names from system_profiler fallback results' do
          placeholder_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                     => 'en0',
                'spairport_airport_local_wireless_networks' => [
                  { '_name' => '<redacted>', 'spairport_signal_noise' => '95/10' },
                  { '_name' => '<hidden>', 'spairport_signal_noise' => '85/10' },
                  { '_name' => 'VisibleNetwork', 'spairport_signal_noise' => '75/10' },
                ],
              }],
            }],
          }

          allow(model).to receive_messages(
            airport_data:           placeholder_data,
            wifi_interface:         'en0',
            connected_network_name: nil
          )

          result = model._available_network_names
          expect(result).to eq(['VisibleNetwork'])
        end

        it 'falls back to system_profiler when helper is blocked by Location Services' do
          result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(
            payload:                   [],
            location_services_blocked: true,
            error_message:             'Location Services denied'
          )
          allow(helper_double).to receive(:scan_networks).and_return(result)
          allow(model).to receive_messages(
            airport_data:           { 'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                     => 'en0',
                'spairport_airport_local_wireless_networks' => [
                  { '_name' => 'VisibleNetwork', 'spairport_signal_noise' => '75/10' },
                ],
              }],
            }] },
            wifi_interface:         'en0',
            connected_network_name: nil
          )

          expect(model._available_network_names).to eq(['VisibleNetwork'])
        end
      end

      describe '#airport_data (private)' do
        it 'parses system_profiler JSON output' do
          json_output = '{"SPAirPortDataType": [{"test": "data"}]}'
          allow(model).to receive(:run_command_using_args).with(
            %w[system_profiler -json SPAirPortDataType],
            true,
            timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
          ).and_return(command_result(stdout: json_output))

          result = model.send(:airport_data)
          expect(result).to eq({ 'SPAirPortDataType' => [{ 'test' => 'data' }] })
        end

        it 'raises error for invalid JSON' do
          allow(model).to receive(:run_command_using_args).and_return(command_result(stdout: 'invalid json'))

          expect { model.send(:airport_data) }.to raise_error(/Failed to parse system_profiler output/)
        end

        it 'memoizes parsed system_profiler data only within a cache scope' do
          first_json_output = '{"SPAirPortDataType": [{"test": "first"}]}'
          second_json_output = '{"SPAirPortDataType": [{"test": "second"}]}'

          expect(model).to receive(:run_command_using_args).with(
            %w[system_profiler -json SPAirPortDataType],
            true,
            timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
          ).twice.and_return(
            command_result(stdout: first_json_output),
            command_result(stdout: second_json_output)
          )

          model.send(:with_airport_data_cache_scope) do
            2.times do
              expect(model.send(:airport_data)).to eq({ 'SPAirPortDataType' => [{ 'test' => 'first' }] })
            end
          end

          model.send(:with_airport_data_cache_scope) do
            expect(model.send(:airport_data)).to eq({ 'SPAirPortDataType' => [{ 'test' => 'second' }] })
          end
        end
      end

      describe '#_connect' do
        it 'clears cached airport data before delegating connect orchestration' do
          transport = instance_double(WifiWand::MacOsWifiTransport)
          allow(model).to receive(:mac_os_wifi_transport).and_return(transport)

          expect(model).to receive(:invalidate_airport_data_cache).ordered
          expect(transport).to receive(:connect).with('TestNetwork', 'password').ordered

          model._connect('TestNetwork', 'password')
        end
      end

      describe '#connection_security_type' do
        let(:network_name) { 'TestNetwork' }
        let(:wifi_interface) { 'en0' }
        let(:connected_airport_data) do
          {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                           => wifi_interface,
                'spairport_airport_other_local_wireless_networks' => [{
                  '_name'                   => network_name,
                  'spairport_security_mode' => 'WPA2',
                }],
                'spairport_current_network_information'           => { '_name' => network_name },
              }],
            }],
          }
        end

        before do
          # wifi_on? is called by connected_network_name, which is called by network_list_key.
          # Stub it so the tests don't attempt a real OS command.
          allow(model).to receive_messages(
            _connected_network_name: network_name,
            wifi_interface:          wifi_interface,
            wifi_on?:                true
          )
        end

        # When connected, system_profiler moves the current SSID to
        # 'spairport_airport_other_local_wireless_networks'. The tests below mirror
        # that layout so they match what network_list_key selects at runtime.
        [
          ['WPA2', 'WPA2'],
          ['WPA3', 'WPA3'],
          ['WPA', 'WPA'],
          ['WPA1', 'WPA'],
          ['WEP', 'WEP'],
          ['spairport_security_mode_none', 'NONE'],
          ['None', 'NONE'],
          ['OWE', 'NONE'],
          ['Unknown Security', nil],
        ].each do |security_mode, expected_result|
          it "returns #{expected_result || 'nil'} for #{security_mode}" do
            airport_data = {
              'SPAirPortDataType' => [{
                'spairport_airport_interfaces' => [{
                  '_name'                                           => wifi_interface,
                  'spairport_airport_other_local_wireless_networks' => [{
                    '_name'                   => network_name,
                    'spairport_security_mode' => security_mode,
                  }],
                  'spairport_current_network_information'           => { '_name' => network_name },
                }],
              }],
            }

            allow(model).to receive(:airport_data).and_return(airport_data)

            expect(model.connection_security_type).to eq(expected_result)
          end
        end

        # Regression: the original code hardcoded 'spairport_airport_local_wireless_networks',
        # which is the wrong key when connected. system_profiler places the current SSID under
        # 'spairport_airport_other_local_wireless_networks' once the interface is associated.
        it 'finds the connected network under other_local_wireless_networks (not local)' do
          airport_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                           => wifi_interface,
                'spairport_airport_other_local_wireless_networks' => [{
                  '_name'                   => network_name,
                  'spairport_security_mode' => 'WPA2',
                }],
                'spairport_airport_local_wireless_networks'       => [],
                'spairport_current_network_information'           => { '_name' => network_name },
              }],
            }],
          }

          allow(model).to receive(:airport_data).and_return(airport_data)

          expect(model.connection_security_type).to eq('WPA2')
        end

        it 'uses one airport snapshot while resolving security for a single lookup' do
          helper_double = instance_double(WifiWand::MacOsWifiAuthHelper::Client)
          json_output = JSON.generate(connected_airport_data)
          helper_result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(payload: nil)

          allow(model).to receive(:_connected_network_name).and_call_original
          allow(model).to receive(:mac_helper_client).and_return(helper_double)
          allow(helper_double).to receive(:connected_network_name).and_return(helper_result)

          expect(model).to receive(:run_command_using_args).with(
            %w[system_profiler -json SPAirPortDataType],
            true,
            timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
          ).once.and_return(command_result(stdout: json_output))

          expect(model.connection_security_type).to eq('WPA2')
        end

        it 'refreshes airport data between separate security lookups' do
          helper_double = instance_double(WifiWand::MacOsWifiAuthHelper::Client)
          helper_result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(payload: nil)
          first_airport_data = JSON.generate(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                           => wifi_interface,
                'spairport_airport_other_local_wireless_networks' => [{
                  '_name'                   => network_name,
                  'spairport_security_mode' => 'WPA2',
                }],
                'spairport_current_network_information'           => { '_name' => network_name },
              }],
            }]
          )
          second_airport_data = JSON.generate(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                           => wifi_interface,
                'spairport_airport_other_local_wireless_networks' => [{
                  '_name'                   => network_name,
                  'spairport_security_mode' => 'WPA3',
                }],
                'spairport_current_network_information'           => { '_name' => network_name },
              }],
            }]
          )

          allow(model).to receive(:_connected_network_name).and_call_original
          allow(model).to receive(:mac_helper_client).and_return(helper_double)
          allow(helper_double).to receive(:connected_network_name).and_return(helper_result)

          expect(model).to receive(:run_command_using_args).with(
            %w[system_profiler -json SPAirPortDataType],
            true,
            timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
          ).twice.and_return(
            command_result(stdout: first_airport_data),
            command_result(stdout: second_airport_data)
          )

          expect(model.connection_security_type).to eq('WPA2')
          expect(model.connection_security_type).to eq('WPA3')
        end

        it 'clears cached airport data before a state-changing operation' do
          json_output = JSON.generate(connected_airport_data)

          expect(model).to receive(:run_command_using_args).with(
            %w[system_profiler -json SPAirPortDataType],
            true,
            timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
          ).twice.and_return(command_result(stdout: json_output))
          allow(model).to receive(:wifi_interface).and_return(wifi_interface)
          allow(model).to receive(:run_command_using_args).with(
            ['networksetup', '-setairportpower', wifi_interface, 'on']
          ).and_return(command_result(stdout: ''))

          expect(model.connection_security_type).to eq('WPA2')
          allow(model).to receive(:wifi_on?).and_return(false, true)
          expect(model.wifi_on).to be_nil
          expect(model.connection_security_type).to eq('WPA2')
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
                '_name'                                           => 'other_interface',
                'spairport_airport_other_local_wireless_networks' => [],
              }],
            }],
          }

          allow(model).to receive(:airport_data).and_return(airport_data)

          expect(model.connection_security_type).to be_nil
        end

        it 'returns nil when connected network not found in scan results' do
          airport_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                           => wifi_interface,
                'spairport_airport_other_local_wireless_networks' => [{
                  '_name'                   => 'OtherNetwork',
                  'spairport_security_mode' => 'WPA2',
                }],
              }],
            }],
          }

          allow(model).to receive(:airport_data).and_return(airport_data)

          expect(model.connection_security_type).to be_nil
        end

        it 'returns nil when security mode information is missing' do
          airport_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                           => wifi_interface,
                'spairport_airport_other_local_wireless_networks' => [{
                  '_name' => network_name,
                  # No spairport_security_mode key
                }],
              }],
            }],
          }

          allow(model).to receive(:airport_data).and_return(airport_data)

          expect(model.connection_security_type).to be_nil
        end
      end

      describe '#network_hidden?' do
        let(:network_name) { 'TestNetwork' }
        let(:wifi_interface) { 'en0' }

        before do
          allow(model).to receive_messages(
            _connected_network_name: network_name,
            wifi_interface:          wifi_interface
          )
        end

        it 'returns false when connected network appears in broadcast list' do
          airport_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                     => wifi_interface,
                'spairport_current_network_information'     => {
                  '_name' => network_name,
                },
                'spairport_airport_local_wireless_networks' => [{
                  '_name'                  => network_name,
                  'spairport_signal_noise' => '50/10',
                }],
              }],
            }],
          }

          allow(model).to receive_messages(airport_data: airport_data, connected_network_name: network_name)

          expect(model.network_hidden?).to be false
        end

        it 'returns true when connected network is not in broadcast list (hidden)' do
          airport_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                     => wifi_interface,
                'spairport_current_network_information'     => {
                  '_name' => network_name,
                },
                'spairport_airport_local_wireless_networks' => [{
                  '_name'                  => 'OtherNetwork',
                  'spairport_signal_noise' => '40/10',
                }],
              }],
            }],
          }

          allow(model).to receive_messages(airport_data: airport_data, connected_network_name: network_name)

          expect(model.network_hidden?).to be true
        end

        it 'returns false when connected visible network appears only in other_local_wireless_networks' do
          airport_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                           => wifi_interface,
                'spairport_current_network_information'           => {
                  '_name' => network_name,
                },
                'spairport_airport_local_wireless_networks'       => [{
                  '_name'                  => 'OtherNetwork',
                  'spairport_signal_noise' => '40/10',
                }],
                'spairport_airport_other_local_wireless_networks' => [{
                  '_name'                  => network_name,
                  'spairport_signal_noise' => '50/10',
                }],
              }],
            }],
          }

          allow(model).to receive_messages(
            airport_data:           airport_data,
            connected_network_name: network_name,
            wifi_on?:               true
          )

          expect(model.network_hidden?).to be false
        end

        it 'returns false when not connected to any network' do
          allow(model).to receive(:_connected_network_name).and_return(nil)

          expect(model.network_hidden?).to be false
        end

        it 'returns false when airport data is unavailable' do
          allow(model).to receive(:airport_data).and_return({})

          expect(model.network_hidden?).to be false
        end

        it 'returns false when wifi interface not found in airport data' do
          airport_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'other_interface',
                'spairport_current_network_information' => {
                  '_name' => network_name,
                },
              }],
            }],
          }

          allow(model).to receive(:airport_data).and_return(airport_data)

          expect(model.network_hidden?).to be false
        end

        it 'returns false when current network information is missing' do
          airport_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name' => wifi_interface,
                # No spairport_current_network_information
              }],
            }],
          }

          allow(model).to receive(:airport_data).and_return(airport_data)

          expect(model.network_hidden?).to be false
        end
      end

      describe '#detect_wifi_service_name edge cases' do
        it 'returns Wi-Fi as final fallback when all detection fails' do
          no_wifi_output = "Hardware Port: Ethernet\nDevice: en1"
          allow(model).to receive(:run_command_using_args).with(%w[networksetup -listallhardwareports])
            .and_return(command_result(stdout: no_wifi_output))
          allow(model).to receive(:wifi_interface).and_return('en0')

          result = model.detect_wifi_service_name
          expect(result).to eq('Wi-Fi')
        end
      end

      describe '#set_nameservers IP validation edge cases' do
        it 'identifies mixed valid and invalid IP addresses (IPv4 and IPv6)' do
          allow(model).to receive(:detect_wifi_service_name).and_return('Wi-Fi')
          mixed_ips = ['8.8.8.8', 'invalid.ip', '2606:4700:4700::1111', '1.1.1.1', '999.999.999.999']

          silence_output do
            expect do
              model.set_nameservers(mixed_ips)
            end.to raise_error(WifiWand::InvalidIPAddressError) do |error|
              expect(error.invalid_addresses).to include('invalid.ip', '999.999.999.999')
              expect(error.invalid_addresses).not_to include('8.8.8.8', '1.1.1.1', '2606:4700:4700::1111')
            end
          end
        end

        it 'treats IPAddr invalid-address errors as invalid input' do
          allow(model).to receive(:detect_wifi_service_name).and_return('Wi-Fi')
          allow(IPAddr).to receive(:new).with('problematic.ip')
            .and_raise(IPAddr::InvalidAddressError, 'Parse error')
          allow(IPAddr).to receive(:new).with('8.8.8.8').and_call_original

          problematic_ips = ['8.8.8.8', 'problematic.ip']
          silence_output do
            expect { model.set_nameservers(problematic_ips) }
              .to raise_error(WifiWand::InvalidIPAddressError) do |error|
                expect(error.invalid_addresses).to eq(['problematic.ip'])
              end
          end
        end
      end
    end

    describe '#create_model with provided interface' do
      context 'when valid wifi_interface is provided' do
        it 'uses the provided interface without probing for another interface',
          :real_env_read_only, real_env_os: :os_mac do
          model = WifiWand::MacOsModel.create_model(wifi_interface: 'en0')
          expect(model.wifi_interface).to eq('en0')
        end
      end

      context 'when invalid wifi_interface is provided' do
        it 'raises InvalidInterfaceError' do
          allow_any_instance_of(WifiWand::MacOsModel).to receive(:is_wifi_interface?).with('invalid0')
            .and_return(false)

          expect { WifiWand::MacOsModel.create_model(wifi_interface: 'invalid0') }
            .to raise_error(WifiWand::InvalidInterfaceError)
        end
      end

      context 'when no wifi_interface is provided' do
        it 'defers interface discovery until wifi_interface is requested' do
          model = WifiWand::MacOsModel.create_model
          expect(model.instance_variable_get(:@wifi_interface)).to be_nil
        end
      end
    end
  end
end
