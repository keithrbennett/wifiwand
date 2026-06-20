# frozen_string_literal: true

require 'json'
require 'timeout'
require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/platforms/mac/model'

module WifiWand
  describe Platforms::Mac::Model do
    let(:helper_query_result) { Platforms::Mac::Helper::Bundle::HelperQueryResult }

    # Prevent accidental Keychain UI prompts in all tests (both real-env and mocked)
    before do
      unless uses_real_env? || RSpec.current_example&.metadata&.[](:keychain_integration)
        # Avoid macOS Keychain prompts during mocked tests
        # rubocop:disable RSpec/AnyInstance -- file-level bootstrap stubs keep mocked model setup hermetic
        allow_any_instance_of(described_class).to receive(:preferred_network_password).and_return(nil)
        # Ensure initialization doesn’t fail due to interface detection during mocked tests
        unless RSpec.current_example&.metadata&.[](:allow_real_probe_wifi_interface)
          allow_any_instance_of(described_class).to receive(:probe_wifi_interface).and_return('en0')
        end

        allow_any_instance_of(WifiWand::NetworkConnectivityTester).to receive(:internet_connectivity_state)
          .and_return(:reachable)
        allow_any_instance_of(WifiWand::NetworkConnectivityTester).to receive(:tcp_connectivity?)
          .and_return(true)
        allow_any_instance_of(WifiWand::NetworkConnectivityTester).to receive(:dns_working?)
          .and_return(true)
        # rubocop:enable RSpec/AnyInstance

      end
    end

    describe 'version support' do
      subject(:model) { create_mac_os_test_model }

      describe '#macos_version' do
        it 'delegates through system network info' do
          system_network_info = instance_double(Platforms::Mac::SystemNetworkInfo)
          allow(model).to receive(:system_network_info).and_return(system_network_info)
          allow(system_network_info).to receive(:detect_macos_version)
            .with(timeout_in_secs: 3)
            .and_return('15.6')

          expect(model.macos_version(timeout_in_secs: 3)).to eq('15.6')
          expect(system_network_info).to have_received(:detect_macos_version)
            .with(timeout_in_secs: 3)
        end

        it 'detects macOS version when command succeeds' do
          model = create_mac_os_test_model
          allow(model).to receive(:run_command).with(%w[sw_vers -productVersion])
            .and_return(command_result(stdout: "15.6\n"))

          expect(model.macos_version).to eq('15.6')
        end

        it 'uses the model command runner for sw_vers detection' do
          model = create_mac_os_test_model
          allow(model).to receive(:run_command).with(%w[sw_vers -productVersion])
            .and_return(command_result(stdout: "15.6\n"))

          model.macos_version

          expect(model).to have_received(:run_command).with(%w[sw_vers -productVersion])
        end

        it 'returns nil when command fails' do
          model = create_mac_os_test_model
          allow(model).to receive(:run_command).with(%w[sw_vers -productVersion])
            .and_raise(
              os_command_error(exitstatus: 1, command: 'sw_vers -productVersion', text: 'Command failed')
            )

          expect { model.macos_version }.not_to raise_error
          expect(model.macos_version).to be_nil
        end
      end

      describe '#wifi_on?' do
        it 'delegates through system network info' do
          system_network_info = instance_double(Platforms::Mac::SystemNetworkInfo)
          allow(model).to receive(:system_network_info).and_return(system_network_info)
          allow(system_network_info).to receive(:wifi_on?).and_return(true)

          expect(model.wifi_on?).to be(true)
          expect(system_network_info).to have_received(:wifi_on?)
        end
      end

      # Network connection tests (highest risk)
      context 'when running network connection operations',
        :real_env_read_write, real_env_os: :os_mac do
        subject { create_mac_os_test_model }

        describe '#_connect' do
          it 'raises connection error for non-existent network' do
            expect { subject._connect('non_existent_network_123') }
              .to raise_error(WifiWand::NetworkConnectionError) do |error|
                expect(error.network_name).to eq('non_existent_network_123')
                expect(error.source).to eq(:swift).or eq(:networksetup)
              end
          end
        end
      end

      context 'when running read-only real-environment inspections',
        :real_env_read_only, real_env_os: :os_mac do
        subject { create_mac_os_test_model }

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
            first_service = subject.wifi_service_name
            expect(first_service).not_to be_nil

            2.times do
              expect(subject.wifi_service_name).to eq(first_service)
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
      let(:identity_reader) { model.send(:network_identity_reader) }
      let(:success_result) do
        WifiWand::CommandExecutor::OsCommandResult.new(
          stdout: '', stderr: '', combined_output: '', exitstatus: 0, command: '', duration: 0.1
        )
      end

      def stub_fast_network_identity_missing(timeout_in_secs: nil)
        allow(model).to receive(:run_command)
          .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: timeout_in_secs)
          .and_return(command_result(stdout: ''))
      end

      describe '#os_id' do
        it 'returns mac symbol' do
          expect(described_class.os_id).to eq(:mac)
        end
      end

      describe '#render_qr_code' do
        it 'renders through the system_profiler WiFi data cache scope' do
          allow(model).to receive_messages(
            command_available?:          true,
            connected_network_name:      'TestNetwork',
            connection_security_type:    'WPA2',
            preferred_network_password:  'secret',
            _preferred_network_password: 'secret',
            network_hidden?:             false
          )
          allow(model).to receive(:run_command)
            .with(
              satisfy { |cmd| cmd.first(5) == %w[qrencode -t ANSI -o -] },
              log_stdout: false, binary_stdout: false
            )
            .and_return(command_result(stdout: "[QR-ANSI]\n"))

          expect(model).to receive(:with_system_profiler_wifi_data_cache_scope).and_yield

          expect(model.render_qr_code(format: :ansi)).to eq("[QR-ANSI]\n")
        end
      end

      describe '#print_qr_code' do
        it 'prints through the system_profiler WiFi data cache scope' do
          model.out_stream = StringIO.new
          allow(model).to receive_messages(
            command_available?:          true,
            connected_network_name:      'TestNetwork',
            connection_security_type:    'WPA2',
            preferred_network_password:  'secret',
            _preferred_network_password: 'secret',
            network_hidden?:             false
          )
          allow(model).to receive(:run_command)
            .with(
              satisfy { |cmd| cmd.first(5) == %w[qrencode -t ANSI -o -] },
              log_stdout: false, binary_stdout: false
            )
            .and_return(command_result(stdout: "[QR-ANSI]\n"))

          expect(model).to receive(:with_system_profiler_wifi_data_cache_scope).and_yield

          expect(model.print_qr_code).to be_nil
          expect(model.out_stream.string).to include('[QR-ANSI]')
        end
      end

      describe '#status_line_data' do
        let(:progress_callback) { ->(_data) {} }

        it 'uses the full connectivity worker timeout for macOS status checks' do
          expect(WifiWand::StatusLineDataBuilder).to receive(:call).with(
            model,
            progress_callback:                          progress_callback,
            runtime_config:                             model.runtime_config,
            expected_network_errors:                    described_class::EXPECTED_NETWORK_ERRORS,
            connectivity_worker_result_timeout_seconds: WifiWand::TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT
          ).and_return({})

          model.status_line_data(progress_callback: progress_callback)
        end
      end

      describe '#wifi_service_name' do
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
            model.instance_variable_set(:@wifi_service_name, nil)
            allow(model).to receive(:run_command)
              .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
              .and_return(command_result(stdout: output))
            expect(model.wifi_service_name).to eq(expected)
          end
        end

        it 'falls back to Wi-Fi when no pattern matches' do
          no_wifi_output = "Hardware Port: Ethernet\nDevice: en1"
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .and_return(command_result(stdout: no_wifi_output))
          allow(model).to receive(:wifi_interface).and_return('en0')
          expect(model.wifi_service_name).to eq('Wi-Fi')
        end

        it 'derives service name from previous Hardware Port line for detected interface' do
          model.instance_variable_set(:@wifi_interface, 'en0')
          model.instance_variable_set(:@wifi_service_name, nil)
          output = "Hardware Port: USB Adapter\nDevice: en0\nEthernet Address: aa:bb:cc:dd:ee:ff\n\n" \
            "Hardware Port: Ethernet\nDevice: en1\n"
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .and_return(command_result(stdout: output))

          expect(model.wifi_service_name).to eq('USB Adapter')
        end
      end

      describe '#is_wifi_interface?' do
        it 'returns true when networksetup confirms the interface is WiFi' do
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listpreferredwirelessnetworks en0])
            .and_return(command_result(stdout: ''))

          expect(model.is_wifi_interface?('en0')).to be(true)
        end

        it 'returns false when networksetup reports a non-WiFi interface' do
          error = os_command_error(exitstatus: 10, command: 'networksetup', text: '')
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listpreferredwirelessnetworks en1])
            .and_raise(error)

          expect(model.is_wifi_interface?('en1')).to be(false)
        end

        it 're-raises unexpected networksetup failures' do
          error = os_command_error(exitstatus: 5, command: 'networksetup', text: 'unexpected failure')
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listpreferredwirelessnetworks en2])
            .and_raise(error)

          expect { model.is_wifi_interface?('en2') }
            .to raise_error(WifiWand::CommandExecutor::OsCommandError, /unexpected failure/)
        end
      end

      describe 'DNS service-name detection' do
        let(:non_wifi_ports_output) { "Hardware Port: Ethernet\nDevice: en1\n" }

        it 'uses a trusted cached service name for DNS commands' do
          model.instance_variable_set(:@wifi_service_name, 'CustomSvc')
          model.instance_variable_set(:@wifi_service_name_source, :detected)
          expect(model).not_to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
          expect(model).to receive(:run_command)
            .with(%w[networksetup -setdnsservers CustomSvc 8.8.8.8])

          expect(model.set_nameservers(['8.8.8.8'])).to eq(['8.8.8.8'])
        end

        it 'caches the strict detected service name used for DNS commands' do
          model.instance_variable_set(:@wifi_interface, 'en1')
          model.instance_variable_set(:@wifi_service_name, nil)
          output = "Hardware Port: AirPort\nDevice: en1\nEthernet Address: aa:bb:cc\n\n" \
            "Hardware Port: Ethernet\nDevice: en0\n"
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .and_return(command_result(stdout: output))
          expect(model).to receive(:run_command)
            .with(%w[networksetup -setdnsservers AirPort 8.8.8.8])

          expect(model.set_nameservers(['8.8.8.8'])).to eq(['8.8.8.8'])
          expect(model.instance_variable_get(:@wifi_service_name)).to eq('AirPort')
        end

        it 'reuses a strictly detected service name for later DNS commands' do
          model.instance_variable_set(:@wifi_interface, 'en1')
          model.instance_variable_set(:@wifi_service_name, nil)
          output = "Hardware Port: AirPort\nDevice: en1\nEthernet Address: aa:bb:cc\n"
          expect(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .once
            .and_return(command_result(stdout: output))
          expect(model).to receive(:run_command)
            .with(%w[networksetup -setdnsservers AirPort 8.8.8.8])
          expect(model).to receive(:run_command)
            .with(%w[networksetup -setdnsservers AirPort 1.1.1.1])

          expect(model.set_nameservers(['8.8.8.8'])).to eq(['8.8.8.8'])
          expect(model.set_nameservers(['1.1.1.1'])).to eq(['1.1.1.1'])
        end

        it 'does not use the public Wi-Fi service-name fallback for DNS writes' do
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .and_return(command_result(stdout: non_wifi_ports_output))
          expect(model).not_to receive(:run_command)
            .with(%w[networksetup -setdnsservers Wi-Fi 8.8.8.8])

          expect { model.set_nameservers(['8.8.8.8']) }.to raise_error(WifiWand::WifiServiceError)
        end

        it 'does not use a cached public Wi-Fi service-name fallback for DNS writes' do
          expect(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .ordered
            .and_return(command_result(stdout: non_wifi_ports_output))
          expect(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .ordered
            .and_return(command_result(stdout: non_wifi_ports_output))
          expect(model).not_to receive(:run_command)
            .with(%w[networksetup -setdnsservers Wi-Fi 8.8.8.8])

          expect(model.wifi_service_name).to eq('Wi-Fi')
          expect { model.set_nameservers(['8.8.8.8']) }.to raise_error(WifiWand::WifiServiceError)
        end

        it 'does not use the public Wi-Fi service-name fallback for DNS reads' do
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .and_return(command_result(stdout: non_wifi_ports_output))
          expect(model).not_to receive(:run_command)
            .with(%w[networksetup -getdnsservers Wi-Fi])

          expect { model.nameservers_using_networksetup }.to raise_error(WifiWand::WifiServiceError)
        end
      end

      describe '#detect_wifi_interface_using_networksetup' do
        it 'extracts WiFi interface from networksetup output' do
          output = "Hardware Port: Wi-Fi\nDevice: en0\nEthernet Address: aa:bb:cc\n\n" \
            "Hardware Port: Ethernet\nDevice: en1\n"
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .and_return(command_result(stdout: output))
          expect(model.detect_wifi_interface_using_networksetup).to eq('en0')
        end

        it 'caches the learned interface and service name from networksetup detection' do
          output = "Hardware Port: AirPort\nDevice: en1\nEthernet Address: aa:bb:cc\n\n" \
            "Hardware Port: Ethernet\nDevice: en0\n"
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .and_return(command_result(stdout: output))

          expect(model.detect_wifi_interface_using_networksetup).to eq('en1')
          expect(model.instance_variable_get(:@wifi_interface)).to eq('en1')
          expect(model.wifi_service_name).to eq('AirPort')
        end

        it 'raises WifiInterfaceError when WiFi service not found' do
          output = "Hardware Port: Ethernet\nDevice: en1\n"
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .and_return(command_result(stdout: output))
          expect do
            model.detect_wifi_interface_using_networksetup
          end.to raise_error(WifiWand::WifiInterfaceError)
        end

        it 'preserves networksetup command failures for direct callers' do
          error = os_command_error(exitstatus: 1, command: 'networksetup', text: 'boom')
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .and_raise(error)

          expect do
            model.detect_wifi_interface_using_networksetup
          end.to raise_error(WifiWand::CommandExecutor::OsCommandError, /boom/)
        end
      end

      describe '#_connected_network_name' do
        let(:helper_double) do
          instance_double(WifiWand::Platforms::Mac::Helper::Client)
        end

        before do
          model.instance_variable_set(:@helper_client, nil)
          allow(WifiWand::Platforms::Mac::Helper::Client).to receive(:new).and_return(helper_double)
        end

        it 'returns the helper-provided SSID when available' do
          result = helper_query_result.new(payload: 'HelperSSID')
          allow(helper_double).to receive(:connected_network_name).and_return(result)

          expect(model._connected_network_name).to eq('HelperSSID')
        end

        it 'uses networksetup for the connected SSID before reading system_profiler WiFi data' do
          result = helper_query_result.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive(:wifi_interface).and_return('en0')
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: nil)
            .and_return(command_result(stdout: "Current Wi-Fi Network: Cafe: West\n"))
          expect(model).not_to receive(:system_profiler_wifi_data)

          expect(model._connected_network_name).to eq('Cafe: West')
        end

        it 'falls through a networksetup placeholder SSID to system_profiler WiFi data' do
          result = helper_query_result.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(system_profiler_wifi_data: { 'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                 => 'en0',
              'spairport_current_network_information' => { '_name' => 'ProfilerNet' },
            }],
          }] }, wifi_interface: 'en0')
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: nil)
            .and_return(command_result(stdout: "Current Wi-Fi Network: <redacted>\n"))

          expect(model._connected_network_name).to eq('ProfilerNet')
        end

        it 'does not read system_profiler WiFi data when networksetup reports no association' do
          result = helper_query_result.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive(:wifi_interface).and_return('en0')
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: nil)
            .and_return(command_result(stdout: "You are not associated with an AirPort network.\n"))
          expect(model).not_to receive(:system_profiler_wifi_data)

          expect(model._connected_network_name).to be_nil
        end

        it 'does not read system_profiler WiFi data when networksetup reports WiFi power is off' do
          result = helper_query_result.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive(:wifi_interface).and_return('en0')
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: nil)
            .and_return(command_result(stdout: "Wi-Fi power is currently off.\n"))
          expect(model).not_to receive(:system_profiler_wifi_data)

          expect(model._connected_network_name).to be_nil
        end

        it 'does not run redaction fallback work when networksetup reports no association' do
          result = helper_query_result.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(wifi_interface: 'en0', wifi_on?: true)
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: nil)
            .and_return(command_result(stdout: "You are not associated with an AirPort network.\n"))
          expect(model).not_to receive(:system_profiler_wifi_data)
          expect(identity_reader).not_to receive(:connected?)

          expect(model.connected_network_name).to be_nil
        end

        %i[unavailable timeout error unknown].each do |helper_status|
          it "returns nil for authoritative not-connected fallback evidence with helper #{helper_status}" do
            result = helper_query_result.new(status: helper_status)
            allow(helper_double).to receive(:connected_network_name).and_return(result)
            allow(model).to receive_messages(wifi_interface: 'en0', wifi_on?: true)
            expect(model).to receive(:run_command)
              .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: nil)
              .and_return(command_result(stdout: "You are not associated with an AirPort network.\n"))
            expect(model).not_to receive(:system_profiler_wifi_data)
            expect(identity_reader).not_to receive(:connected?)

            expect(model.connected_network_name).to be_nil
          end
        end

        it 'falls back to system_profiler WiFi data when helper returns nil' do
          result = helper_query_result.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(system_profiler_wifi_data: { 'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                 => 'en0',
              'spairport_current_network_information' => { '_name' => 'ProfilerNet' },
            }],
          }] }, wifi_interface: 'en0')
          stub_fast_network_identity_missing

          expect(model._connected_network_name).to eq('ProfilerNet')
        end

        it 'returns nil when helper returns nil and system_profiler WiFi data is missing ' \
          'current network information' do
          result = helper_query_result.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(system_profiler_wifi_data: { 'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                 => 'en0',
              'spairport_current_network_information' => nil,
            }],
          }] }, wifi_interface: 'en0')
          stub_fast_network_identity_missing

          expect(model._connected_network_name).to be_nil
        end

        it 'does not fall back to system_profiler WiFi data when the helper explicitly ' \
          'reports not connected' do
          result = helper_query_result.new(status: :not_connected)
          allow(helper_double).to receive(:connected_network_name).and_return(result)

          expect(model).not_to receive(:system_profiler_wifi_data)
          expect(model._connected_network_name).to be_nil
        end

        it 'falls back to system_profiler WiFi data when helper is blocked by Location Services' do
          result = helper_query_result.new(
            location_services_blocked: true,
            error_message:             'Location Services denied'
          )
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(system_profiler_wifi_data: { 'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                 => 'en0',
              'spairport_current_network_information' => { '_name' => 'ProfilerNet' },
            }],
          }] }, wifi_interface: 'en0')
          stub_fast_network_identity_missing

          expect(model._connected_network_name).to eq('ProfilerNet')
        end

        it 'refreshes connected network state across separate public read operations' do
          result = helper_query_result.new(payload: nil)
          first_system_profiler_wifi_data = JSON.generate(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => { '_name' => 'ProfilerNetA' },
              }],
            }]
          )
          second_system_profiler_wifi_data = JSON.generate(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => { '_name' => 'ProfilerNetB' },
              }],
            }]
          )

          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(wifi_interface: 'en0', wifi_on?: true)
          stub_fast_network_identity_missing
          expect(model).to receive(:run_command).with(
            %w[system_profiler -json SPAirPortDataType],
            raise_on_error:  true,
            timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
          ).twice.and_return(
            command_result(stdout: first_system_profiler_wifi_data),
            command_result(stdout: second_system_profiler_wifi_data)
          )

          expect(model.connected_network_name).to eq('ProfilerNetA')
          expect(model.connected_network_name).to eq('ProfilerNetB')
        end

        it 'isolates connected-network diagnostic flags across concurrent callers' do
          redacted_thread_entered_connected = Queue.new
          release_redacted_thread = Queue.new
          redacted_result = Queue.new
          disconnected_result = Queue.new
          redacted_thread = nil
          disconnected_thread = nil

          reader = identity_reader
          reader.define_singleton_method(:wifi_on?) { true }
          reader.define_singleton_method(:connected_network_name_raw) do
            case Thread.current[:connected_network_name_test_mode]
            when :redacted
              send(:mark_connected_network_fallback_identity_redacted)
            when :disconnected
              send(:mark_connected_network_authoritatively_disconnected)
            else
              raise 'unexpected connected-network test mode'
            end
          end
          reader.define_singleton_method(:connected?) do
            raise 'authoritative disconnect should return before connected?' unless
              Thread.current[:connected_network_name_test_mode] == :redacted

            redacted_thread_entered_connected << true
            release_redacted_thread.pop
            true
          end
          reader.define_singleton_method(:network_identity_redacted?) do
            send(:connected_network_fallback_identity_redacted?)
          end

          begin
            redacted_thread = Thread.new do
              Thread.current[:connected_network_name_test_mode] = :redacted
              redacted_result << model.connected_network_name
            rescue => e
              redacted_result << e
            end

            Timeout.timeout(2) { redacted_thread_entered_connected.pop }

            disconnected_thread = Thread.new do
              Thread.current[:connected_network_name_test_mode] = :disconnected
              disconnected_result << model.connected_network_name
            rescue => e
              disconnected_result << e
            end

            expect(Timeout.timeout(2) { disconnected_result.pop }).to be_nil

            release_redacted_thread << true

            expect(Timeout.timeout(2) { redacted_result.pop }).to be_a(WifiWand::MacOsRedactionError)
          ensure
            release_redacted_thread << true if redacted_thread&.alive?
            [redacted_thread, disconnected_thread].compact.each(&:join)
          end
        end

        it 'raises a targeted exact-identity error when macOS redacts the current SSID' do
          result = helper_query_result.new(
            payload:                   nil,
            location_services_blocked: true,
            error_message:             'Location Services denied'
          )
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(
            wifi_on?:                  true,
            system_profiler_wifi_data: { 'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => { '_name' => nil },
              }],
            }] },
            wifi_interface:            'en0'
          )
          stub_fast_network_identity_missing

          expect { model.connected_network_name }.to raise_error(
            WifiWand::MacOsRedactionError,
            /Exact WiFi network identity.*wifiwand-macos-setup.*wifiwand-helper/
          )
        end

        it 'preserves redaction errors from connection readiness checks' do
          result = helper_query_result.new(
            payload:                   nil,
            location_services_blocked: true,
            error_message:             'Location Services denied'
          )
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(
            wifi_on?:                  true,
            system_profiler_wifi_data: { 'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => { '_name' => nil },
              }],
            }] },
            wifi_interface:            'en0'
          )
          stub_fast_network_identity_missing

          expect { model.connection_ready?('TestNetwork') }.to raise_error(
            WifiWand::MacOsRedactionError,
            /Exact WiFi network identity.*wifiwand-macos-setup.*wifiwand-helper/
          )
        end

        [
          ['Location Services authorization timed out', :timeout],
          ['Location Services authorization status is unknown', :unknown],
        ].each do |helper_error_message, helper_status|
          it "preserves the exact-identity error for #{helper_status} Location Services helper errors" do
            result = helper_query_result.new(
              payload:                   nil,
              location_services_blocked: false,
              error_message:             helper_error_message,
              status:                    helper_status
            )
            allow(helper_double).to receive(:connected_network_name).and_return(result)
            allow(model).to receive_messages(
              wifi_on?:                  true,
              system_profiler_wifi_data: { 'SPAirPortDataType' => [{
                'spairport_airport_interfaces' => [{
                  '_name'                                 => 'en0',
                  'spairport_current_network_information' => { '_name' => nil },
                }],
              }] },
              wifi_interface:            'en0'
            )
            stub_fast_network_identity_missing

            expect { model.connected_network_name }.to raise_error(
              WifiWand::MacOsRedactionError,
              /Exact WiFi network identity.*wifiwand-macos-setup.*wifiwand-helper/
            )
          end
        end

        [
          ['helper unavailable and fallback reports a hidden SSID', :unavailable, '<hidden>'],
          ['helper timeout and fallback reports a redacted SSID', :timeout, '<redacted>'],
          ['helper error and fallback reports a blank SSID', :error, ''],
          ['helper unknown and fallback reports a nil SSID', :unknown, nil],
        ].each do |description, helper_status, fallback_ssid|
          it "raises a targeted exact-identity error when #{description}" do
            result = helper_query_result.new(status: helper_status)
            allow(helper_double).to receive(:connected_network_name).and_return(result)
            allow(model).to receive_messages(
              wifi_on?:                  true,
              system_profiler_wifi_data: { 'SPAirPortDataType' => [{
                'spairport_airport_interfaces' => [{
                  '_name'                                 => 'en0',
                  'spairport_current_network_information' => {
                    '_name'                  => fallback_ssid,
                    'spairport_signal_noise' => '95/10',
                  },
                }],
              }] },
              wifi_interface:            'en0'
            )
            stub_fast_network_identity_missing

            expect { model.connected_network_name }.to raise_error(
              WifiWand::MacOsRedactionError,
              /Exact WiFi network identity.*wifiwand-macos-setup.*wifiwand-helper/
            )
          end
        end

        it 'reuses the current system_profiler WiFi snapshot when fallback evidence proves redaction' do
          result = helper_query_result.new(status: :timeout)
          system_profiler_wifi_json = JSON.generate(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => {
                  '_name'                  => nil,
                  'spairport_signal_noise' => '95/10',
                },
              }],
            }]
          )
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(wifi_on?: true, wifi_interface: 'en0')
          stub_fast_network_identity_missing
          expect(model).to receive(:run_command).with(
            %w[system_profiler -json SPAirPortDataType],
            raise_on_error:  true,
            timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
          ).once.and_return(command_result(stdout: system_profiler_wifi_json))

          expect { model.connected_network_name }.to raise_error(WifiWand::MacOsRedactionError)
        end
      end

      describe '#associated?' do
        let(:helper_double) do
          instance_double(WifiWand::Platforms::Mac::Helper::Client)
        end

        before do
          model.instance_variable_set(:@helper_client, nil)
          allow(WifiWand::Platforms::Mac::Helper::Client).to receive(:new).and_return(helper_double)
          allow(model).to receive_messages(wifi_on?: true, wifi_interface: 'en0')
        end

        it 'returns true when the helper provides a real SSID' do
          result = helper_query_result.new(payload: 'MyNetwork')
          allow(helper_double).to receive(:connected_network_name).and_return(result)

          expect(model).not_to receive(:system_profiler_wifi_data)
          expect(model.associated?).to be(true)
        end

        it 'returns true when system_profiler WiFi data shows non-empty current network information ' \
          'without an SSID name' do
          result = helper_query_result.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive(:system_profiler_wifi_data).and_return(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => { 'spairport_network_channel' => '6' },
              }],
            }]
          )

          expect(model.associated?).to be(true)
        end

        it 'returns false when system_profiler WiFi data only has an empty current-network hash' do
          result = helper_query_result.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive(:system_profiler_wifi_data).and_return(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => {},
              }],
            }]
          )

          expect(model.associated?).to be(false)
        end

        it 'returns false without fallback when the helper explicitly reports not connected' do
          result = helper_query_result.new(status: :not_connected)
          allow(helper_double).to receive(:connected_network_name).and_return(result)

          expect(model).not_to receive(:system_profiler_wifi_data)
          expect(model.associated?).to be(false)
        end

        it 'returns false when the helper reports no SSID and system_profiler WiFi data ' \
          'has no current network info' do
          result = helper_query_result.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive(:system_profiler_wifi_data).and_return(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{ '_name' => 'en0' }],
            }]
          )

          expect(model.associated?).to be(false)
        end
      end

      describe '#disconnect_association_state' do
        context 'when SSID is redacted (Location Services blocked)' do
          it 'uses connected? so default-route or IP evidence can still trigger disconnect' do
            redaction_error = WifiWand::MacOsRedactionError.new(
              operation_description: 'current WiFi network queries'
            )
            allow(model).to receive(:connected_network_name).and_raise(redaction_error)
            allow(model).to receive(:connected?).and_return(true)

            expect(model.send(:disconnect_association_state)).to eq(
              associated:   true,
              network_name: nil
            )
          end

          it 'treats redacted SSID reads as disassociated when connected? is false' do
            redaction_error = WifiWand::MacOsRedactionError.new(
              operation_description: 'current WiFi network queries'
            )
            allow(model).to receive(:connected_network_name).and_raise(redaction_error)
            allow(model).to receive(:connected?).and_return(false)

            expect(model.send(:disconnect_association_state)).to eq(
              associated:   false,
              network_name: nil
            )
          end
        end
      end

      describe '#bssid' do
        let(:bssid_helper_client) { instance_double(WifiWand::Platforms::Mac::Helper::Client) }

        it 'returns the helper-provided current BSSID' do
          result = helper_query_result.new(payload: 'aa:bb:cc:dd:ee:ff', status: :connected)
          allow(model).to receive(:helper_client).and_return(bssid_helper_client)
          expect(bssid_helper_client).to receive(:connected_network_bssid).and_return(result)
          expect(model).not_to receive(:run_command)

          expect(model.bssid).to eq('aa:bb:cc:dd:ee:ff')
        end

        it 'returns nil when the helper cannot provide a BSSID' do
          result = helper_query_result.new(status: :unknown)
          allow(model).to receive(:helper_client).and_return(bssid_helper_client)
          expect(bssid_helper_client).to receive(:connected_network_bssid).and_return(result)

          expect(model.bssid).to be_nil
        end
      end

      describe '#connected?' do
        let(:helper_double) do
          instance_double(WifiWand::Platforms::Mac::Helper::Client)
        end

        before do
          model.instance_variable_set(:@helper_client, nil)
          allow(WifiWand::Platforms::Mac::Helper::Client).to receive(:new).and_return(helper_double)
          allow(model).to receive(:wifi_on?).and_return(true)
        end

        it 'returns true when the helper provides a real SSID (Sonoma redaction case)' do
          result = helper_query_result.new(payload: 'MyNetwork')
          allow(helper_double).to receive(:connected_network_name).and_return(result)

          expect(model).not_to receive(:system_profiler_wifi_data)
          expect(model.connected?).to be(true)
        end

        it 'returns false when wifi is off, without consulting the helper' do
          allow(model).to receive(:wifi_on?).and_return(false)

          expect(helper_double).not_to receive(:connected_network_name)
          expect(model.connected?).to be(false)
        end

        it 'falls back to system_profiler when helper returns nil' do
          result = helper_query_result.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(
            system_profiler_wifi_data: { 'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => { '_name' => 'SomeNet' },
              }],
            }] },
            wifi_interface:            'en0'
          )

          expect(model.connected?).to be(true)
        end

        it 'returns false when helper returns nil and system_profiler lacks current-network info' do
          result = helper_query_result.new
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(
            system_profiler_wifi_data: { 'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name' => 'en0',
              }],
            }] },
            wifi_interface:            'en0',
            default_interface:         nil,
            _ipv4_addresses:           [],
            _ipv6_addresses:           []
          )

          expect(model.connected?).to be(false)
        end

        it 'returns false without fallback when the helper explicitly reports not connected' do
          result = helper_query_result.new(status: :not_connected)
          allow(helper_double).to receive(:connected_network_name).and_return(result)

          expect(model).not_to receive(:system_profiler_wifi_data)
          expect(model.connected?).to be(false)
        end

        it 'does not treat a placeholder SSID from the helper as connected' do
          result = helper_query_result.new(payload: '<redacted>')
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(
            system_profiler_wifi_data: { 'SPAirPortDataType' => [{ 'spairport_airport_interfaces' => [] }] },
            wifi_interface:            'en0',
            default_interface:         nil,
            _ipv4_addresses:           [],
            _ipv6_addresses:           []
          )

          expect(model.connected?).to be(false)
        end

        it 'returns true when association evidence exists but SSID is redacted' do
          result = helper_query_result.new(
            location_services_blocked: true,
            error_message:             'Location Services denied'
          )
          allow(helper_double).to receive(:connected_network_name).and_return(result)
          allow(model).to receive_messages(
            system_profiler_wifi_data: { 'SPAirPortDataType' => [{ 'spairport_airport_interfaces' => [{
              '_name' => 'en0',
            }] }] },
            wifi_interface:            'en0',
            default_interface:         'en0'
          )
          allow(model).to receive(:_ipv4_addresses).and_return([])

          expect(model.connected?).to be(true)
        end

        it 'returns true when the helper is disabled and the WiFi interface still has an IP address' do
          allow(WifiWand::Platforms::Mac::Helper::Client).to receive(:new).and_call_original
          helper_client = WifiWand::Platforms::Mac::Helper::Client.new(
            out_stream_provider:  -> { $stdout },
            err_stream_provider:  -> { $stderr },
            verbosity_provider:   -> { false },
            macos_version_reader: ->(timeout_in_secs: nil) { '14.0' }
          )
          model.instance_variable_set(:@helper_client, helper_client)
          allow(model).to receive_messages(
            system_profiler_wifi_data: { 'SPAirPortDataType' => [{ 'spairport_airport_interfaces' => [{
              '_name' => 'en0',
            }] }] },
            wifi_interface:            'en0',
            default_interface:         nil,
            _ipv4_addresses:           ['192.168.1.44']
          )

          original_env = ENV['WIFIWAND_DISABLE_MAC_HELPER']
          ENV['WIFIWAND_DISABLE_MAC_HELPER'] = '1'
          begin
            expect(WifiWand::Platforms::Mac::Helper::Bundle).not_to receive(:ensure_helper_installed)
            expect(WifiWand::Platforms::Mac::Helper::Bundle).not_to receive(:run_bounded_helper_command)
            expect(model.connected?).to be(true)
          ensure
            ENV['WIFIWAND_DISABLE_MAC_HELPER'] = original_env
          end
        end
      end

      describe '#status_network_identity' do
        let(:helper_double) { instance_double(WifiWand::Platforms::Mac::Helper::Client) }
        let(:status_timeout) { be_between(0, 0.5).exclusive }
        let(:swift_runtime) { instance_double(WifiWand::Platforms::Mac::Helper::SwiftRuntime) }

        before do
          model.instance_variable_set(:@helper_client, nil)
          model.wifi_interface = 'en0'
          allow(WifiWand::Platforms::Mac::Helper::Client).to receive(:new).and_return(helper_double)
        end

        it 'returns disconnected when status interface detection returns nil' do
          model.instance_variable_set(:@wifi_interface, nil)

          expect(model).to receive(:probe_wifi_interface)
            .with(timeout_in_secs: status_timeout)
            .and_return(nil)
          expect(model).not_to receive(:run_command)
          expect(helper_double).not_to receive(:connected_network_name)

          expect(model.status_network_identity(timeout_in_secs: 0.5)).to eq(
            connected:      false,
            network_name:   nil,
            signal_quality: nil
          )
          expect(model.instance_variable_get(:@wifi_interface)).to be_nil
        end

        it 'initializes a missing interface without probing the Swift mutation runtime' do
          model.instance_variable_set(:@wifi_interface, nil)
          allow(model).to receive(:swift_runtime).and_return(swift_runtime)

          expect(swift_runtime).not_to receive(:swift_and_corewlan_present?)
          expect(model).to receive(:probe_wifi_interface)
            .with(timeout_in_secs: status_timeout)
            .and_return('en0')
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportpower', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: "Wi-Fi Power (en0): On\n"))
          expect(helper_double).to receive(:connected_network_name)
            .with(timeout_seconds: status_timeout)
            .and_return(helper_query_result.new(
              payload:        'HelperSSID',
              signal_quality: WifiWand::SignalQuality.new(value: -65, unit: :dbm)
            ))

          expect(model.status_network_identity(timeout_in_secs: 0.5)).to eq(
            connected:      true,
            network_name:   'HelperSSID',
            signal_quality: WifiWand::SignalQuality.new(value: -65, unit: :dbm)
          )
          expect(model.instance_variable_get(:@wifi_interface)).to eq('en0')
        end

        it 'returns the helper SSID and passes the status budget into the helper lookup' do
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportpower', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: "Wi-Fi Power (en0): On\n"))
          expect(helper_double).to receive(:connected_network_name)
            .with(timeout_seconds: status_timeout)
            .and_return(helper_query_result.new(
              payload:        'HelperSSID',
              signal_quality: WifiWand::SignalQuality.new(value: -65, unit: :dbm)
            ))
          expect(model).not_to receive(:system_profiler_wifi_data)
          expect(model.status_network_identity(timeout_in_secs: 0.5)).to eq(
            connected:      true,
            network_name:   'HelperSSID',
            signal_quality: WifiWand::SignalQuality.new(value: -65, unit: :dbm)
          )
        end

        it 'uses networksetup for status identity before bounded system_profiler WiFi data' do
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportpower', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: "Wi-Fi Power (en0): On\n"))
          expect(helper_double).to receive(:connected_network_name)
            .with(timeout_seconds: status_timeout)
            .and_return(helper_query_result.new)
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: "Current Wi-Fi Network: Cafe: West\n"))
          expect(model).not_to receive(:system_profiler_wifi_data)

          expect(model.status_network_identity(timeout_in_secs: 0.5)).to eq(
            connected:      true,
            network_name:   'Cafe: West',
            signal_quality: nil
          )
        end

        it 'returns disconnected when networksetup reports no association during status' do
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportpower', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: "Wi-Fi Power (en0): On\n"))
          expect(helper_double).to receive(:connected_network_name)
            .with(timeout_seconds: status_timeout)
            .and_return(helper_query_result.new)
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: "You are not associated with an AirPort network.\n"))
          expect(model).not_to receive(:system_profiler_wifi_data)

          expect(model.status_network_identity(timeout_in_secs: 0.5)).to eq(
            connected:      false,
            network_name:   nil,
            signal_quality: nil
          )
        end

        it 'recomputes the remaining status budget before bounded system_profiler WiFi data fallback' do
          system_profiler_wifi_json = JSON.generate(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => {
                  '_name'                  => 'ProfilerNet',
                  'spairport_signal_noise' => '-65/-95',
                },
              }],
            }]
          )
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportpower', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: "Wi-Fi Power (en0): On\n"))
          expect(helper_double).to receive(:connected_network_name)
            .with(timeout_seconds: status_timeout)
            .and_return(helper_query_result.new)
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: status_timeout)
            .and_wrap_original do |_method|
              sleep 0.05
              command_result(stdout: '')
            end
          expect(model).to receive(:run_command)
            .with(
              %w[system_profiler -json SPAirPortDataType],
              raise_on_error:  true,
              timeout_in_secs: be_between(0, 0.45).exclusive
            )
            .and_return(command_result(stdout: system_profiler_wifi_json))

          expect(model.status_network_identity(timeout_in_secs: 0.5)).to eq(
            connected:      true,
            network_name:   'ProfilerNet',
            signal_quality: WifiWand::SignalQuality.new(value: -65, unit: :dbm)
          )
        end

        it 'falls back to bounded system_profiler WiFi data when the helper has no SSID' do
          system_profiler_wifi_json = JSON.generate(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'en0',
                'spairport_current_network_information' => {
                  '_name'                  => 'ProfilerNet',
                  'spairport_signal_noise' => '-65/-95',
                },
              }],
            }]
          )
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportpower', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: "Wi-Fi Power (en0): On\n"))
          expect(helper_double).to receive(:connected_network_name)
            .with(timeout_seconds: status_timeout)
            .and_return(helper_query_result.new)
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: ''))
          expect(model).to receive(:run_command)
            .with(
              %w[system_profiler -json SPAirPortDataType],
              raise_on_error:  true,
              timeout_in_secs: status_timeout
            )
            .and_return(command_result(stdout: system_profiler_wifi_json))

          expect(model.status_network_identity(timeout_in_secs: 0.5)).to eq(
            connected:      true,
            network_name:   'ProfilerNet',
            signal_quality: WifiWand::SignalQuality.new(value: -65, unit: :dbm)
          )
        end

        it 'preserves bounded system_profiler WiFi data timeouts for status fallback handling' do
          timeout_error = WifiWand::CommandTimeoutError.new(
            command:         'system_profiler',
            timeout_in_secs: 0.1
          )

          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportpower', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: "Wi-Fi Power (en0): On\n"))
          expect(helper_double).to receive(:connected_network_name)
            .with(timeout_seconds: status_timeout)
            .and_return(helper_query_result.new)
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: ''))
          expect(model).to receive(:run_command)
            .with(
              %w[system_profiler -json SPAirPortDataType],
              raise_on_error:  true,
              timeout_in_secs: status_timeout
            )
            .and_raise(timeout_error)

          expect { model.status_network_identity(timeout_in_secs: 0.5) }
            .to raise_error(WifiWand::CommandTimeoutError)
        end

        it 'returns disconnected when the helper explicitly reports not connected' do
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportpower', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: "Wi-Fi Power (en0): On\n"))
          expect(helper_double).to receive(:connected_network_name)
            .with(timeout_seconds: status_timeout)
            .and_return(helper_query_result.new(status: :not_connected))

          expect(model).not_to receive(:system_profiler_wifi_data)
          expect(model.status_network_identity(timeout_in_secs: 0.5)).to eq(
            connected:      false,
            network_name:   nil,
            signal_quality: nil
          )
        end

        it 'uses bounded association fallback when system_profiler WiFi data has no SSID' do
          system_profiler_wifi_json = JSON.generate(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{ '_name' => 'en0' }],
            }]
          )
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportpower', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: "Wi-Fi Power (en0): On\n"))
          expect(helper_double).to receive(:connected_network_name)
            .with(timeout_seconds: status_timeout)
            .and_return(helper_query_result.new)
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: ''))
          expect(model).to receive(:run_command)
            .with(
              %w[system_profiler -json SPAirPortDataType],
              raise_on_error:  true,
              timeout_in_secs: status_timeout
            )
            .and_return(command_result(stdout: system_profiler_wifi_json))
          expect(model).to receive(:run_command)
            .with(%w[route -n get default], raise_on_error: false, timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: "interface: en0\n"))

          expect(model.status_network_identity(timeout_in_secs: 0.5)).to eq(
            connected:      true,
            network_name:   nil,
            signal_quality: nil
          )
        end

        it 'treats an empty bounded IP address result as disconnected' do
          system_profiler_wifi_json = JSON.generate(
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{ '_name' => 'en0' }],
            }]
          )
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportpower', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: "Wi-Fi Power (en0): On\n"))
          expect(helper_double).to receive(:connected_network_name)
            .with(timeout_seconds: status_timeout)
            .and_return(helper_query_result.new)
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: ''))
          expect(model).to receive(:run_command)
            .with(
              %w[system_profiler -json SPAirPortDataType],
              raise_on_error:  true,
              timeout_in_secs: status_timeout
            )
            .and_return(command_result(stdout: system_profiler_wifi_json))
          expect(model).to receive(:run_command)
            .with(%w[route -n get default], raise_on_error: false, timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: "interface: en1\n"))
          expect(model).to receive(:run_command)
            .with(%w[ifconfig en0], timeout_in_secs: status_timeout)
            .twice
            .and_return(command_result(stdout: ''))

          expect(model.status_network_identity(timeout_in_secs: 0.5)).to eq(
            connected:      false,
            network_name:   nil,
            signal_quality: nil
          )
        end
      end

      describe '#wifi_info' do
        it 'distinguishes macOS SSID redaction from disconnection' do
          redaction_error = WifiWand::MacOsRedactionError.new(
            operation_description: 'Current WiFi network queries'
          )
          allow(model).to receive_messages(
            wifi_on?:          true,
            wifi_interface:    'en0',
            connected?:        true,
            default_interface: 'en0',
            ipv4_addresses:    ['192.168.1.25'],
            ipv6_addresses:    ['2001:db8::25'],
            mac_address:       'aa:bb:cc:dd:ee:ff',
            nameservers:       ['8.8.8.8']
          )
          allow(model).to receive(:connected_network_name).and_raise(redaction_error)

          info = model.wifi_info

          expect(info).to include(
            'connected'               => true,
            'network'                 => nil,
            'ssid_identity_available' => false,
            'ssid_identity_status'    => 'unavailable'
          )
          expect(info.fetch('ssid_identity_warning')).to include('Location Services')
        end
      end

      describe '#signal_quality' do
        let(:helper_double) { instance_double(WifiWand::Platforms::Mac::Helper::Client) }

        before do
          model.instance_variable_set(:@helper_client, nil)
          allow(WifiWand::Platforms::Mac::Helper::Client).to receive(:new).and_return(helper_double)
        end

        it 'uses helper RSSI before system_profiler data' do
          signal_quality = WifiWand::SignalQuality.new(value: -65, unit: :dbm)
          expect(helper_double).to receive(:connected_network_name)
            .and_return(helper_query_result.new(payload: 'HelperSSID', signal_quality: signal_quality))
          expect(model).not_to receive(:system_profiler_wifi_data)

          expect(model.signal_quality).to eq(signal_quality)
        end

        it 'falls back when the helper cannot provide RSSI' do
          fallback_details = instance_double(
            WifiWand::Platforms::Mac::CurrentNetworkDetails,
            signal_quality: WifiWand::SignalQuality.new(value: -72, unit: :dbm)
          )
          expect(helper_double).to receive(:connected_network_name)
            .and_return(helper_query_result.new(payload: 'HelperSSID'))
          allow(model).to receive(:current_network_details).and_return(fallback_details)

          expect(model.signal_quality).to eq(WifiWand::SignalQuality.new(value: -72, unit: :dbm))
        end

        it 'returns nil when the helper reports no connection' do
          expect(helper_double).to receive(:connected_network_name)
            .and_return(helper_query_result.new(status: :not_connected))
          expect(model).not_to receive(:current_network_details)

          expect(model.signal_quality).to be_nil
        end
      end

      describe '#status_wifi_on?' do
        let(:status_timeout) { be_between(0, 0.5).exclusive }
        let(:read_path_timeout) { be_between(0.45, 0.5).exclusive }
        let(:swift_runtime) { instance_double(WifiWand::Platforms::Mac::Helper::SwiftRuntime) }

        it 'initializes a missing interface without probing the Swift mutation runtime' do
          model.instance_variable_set(:@wifi_interface, nil)
          allow(model).to receive(:swift_runtime).and_return(swift_runtime)

          expect(swift_runtime).not_to receive(:swift_and_corewlan_present?)
          expect(model).to receive(:probe_wifi_interface)
            .with(timeout_in_secs: status_timeout)
            .and_return('en0')
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportpower', 'en0'], timeout_in_secs: status_timeout)
            .and_return(command_result(stdout: "Wi-Fi Power (en0): On\n"))

          expect(model.status_wifi_on?(timeout_in_secs: 0.5)).to be(true)
          expect(model.instance_variable_get(:@wifi_interface)).to eq('en0')
        end

        it 'preserves the bounded status deadline for the airport power lookup' do
          model.instance_variable_set(:@wifi_interface, nil)
          allow(model).to receive(:swift_runtime).and_return(swift_runtime)

          expect(swift_runtime).not_to receive(:swift_and_corewlan_present?)
          expect(model).to receive(:probe_wifi_interface)
            .with(timeout_in_secs: read_path_timeout)
            .and_return('en0')
          expect(model).to receive(:run_command)
            .with(['networksetup', '-getairportpower', 'en0'], timeout_in_secs: read_path_timeout)
            .and_return(command_result(stdout: "Wi-Fi Power (en0): On\n"))

          expect(model.status_wifi_on?(timeout_in_secs: 0.5)).to be(true)
        end
      end

      describe 'Sonoma SSID redaction: helper succeeds but system_profiler lacks current-network data' do
        let(:helper_double) { instance_double(WifiWand::Platforms::Mac::Helper::Client) }
        let(:system_profiler_wifi_data_without_current_network) do
          { 'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{ '_name' => 'en0' }],
          }] }
        end

        before do
          model.instance_variable_set(:@helper_client, nil)
          allow(WifiWand::Platforms::Mac::Helper::Client).to receive(:new).and_return(helper_double)
          allow(model).to receive_messages(
            wifi_on?:                  true,
            wifi_interface:            'en0',
            system_profiler_wifi_data: system_profiler_wifi_data_without_current_network
          )
          # Helper returns real SSID; system_profiler has no current-network key
          helper_ssid_result = helper_query_result.new(payload: 'SonomaNet')
          allow(helper_double).to receive(:connected_network_name).and_return(helper_ssid_result)
        end

        it 'connected? returns true' do
          expect(model.connected?).to be(true)
        end

        it 'connection_ready? succeeds when the network name matches' do
          expect(model.connection_ready?('SonomaNet')).to be(true)
        end

        it 'ipv4_addresses does not raise and delegates to _ipv4_addresses' do
          allow(model).to receive(:_ipv4_addresses).and_return(['10.0.0.42'])
          expect(model.ipv4_addresses).to eq(['10.0.0.42'])
        end

        it 'ipv6_addresses does not raise and delegates to _ipv6_addresses' do
          allow(model).to receive(:_ipv6_addresses).and_return(['2001:db8::42'])
          expect(model.ipv6_addresses).to eq(['2001:db8::42'])
        end
      end

      describe '#remove_preferred_network' do
        let(:sudo_check_command) { %w[sudo -n true] }

        def stub_sudo_tty_stream(stream, responds_to_tty:, tty: true)
          allow(stream).to receive(:respond_to?).and_call_original
          allow(stream).to receive(:respond_to?).with(:tty?).and_return(responds_to_tty)
          allow(stream).to receive(:tty?)
          allow(stream).to receive(:tty?).and_return(tty) if responds_to_tty
        end

        def stub_sudo_tty_streams(stdin_tty: true, stderr_tty: true)
          stub_sudo_tty_stream($stdin, responds_to_tty: true, tty: stdin_tty)
          stub_sudo_tty_stream($stderr, responds_to_tty: true, tty: stderr_tty)
        end

        it 'constructs a correctly escaped removal command for various network names' do
          allow(model).to receive(:wifi_interface).and_return('en0')
          allow(model).to receive(:run_command).with(
            sudo_check_command,
            raise_on_error:  false,
            timeout_in_secs: described_class::SUDO_AUTH_CHECK_TIMEOUT_SECONDS
          ).and_return(success_result)

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
            expect(model).to receive(:run_command).with(
              expected_command_array,
              raise_on_error:  true,
              timeout_in_secs: described_class::SUDO_NETWORKSETUP_TIMEOUT_SECONDS
            )
            expect(model.remove_preferred_network(network_name)).to eq([network_name])
          end
        end

        it 'prompts for sudo authentication when no cached credential is available interactively' do
          err_stream = StringIO.new
          model = create_mac_os_test_model(err_stream: err_stream)
          allow(model).to receive_messages(
            wifi_interface:                             'en0',
            interactive_sudo_authentication_available?: true
          )
          allow(model).to receive(:run_command).with(
            sudo_check_command,
            raise_on_error:  false,
            timeout_in_secs: described_class::SUDO_AUTH_CHECK_TIMEOUT_SECONDS
          ).and_return(command_result(exitstatus: 1, stderr: 'sudo: a password is required'))
          allow(model).to receive(:run_command).with(
            %w[sudo networksetup -removepreferredwirelessnetwork en0 CafeNet],
            raise_on_error:  true,
            timeout_in_secs: described_class::SUDO_NETWORKSETUP_TIMEOUT_SECONDS
          ).and_return(success_result)
          expect(model).to receive(:system).with('sudo', '-v').and_return(true)

          expect(model.remove_preferred_network('CafeNet')).to eq(['CafeNet'])
          expect(err_stream.string).to include(
            'Administrator authentication is required to remove a saved WiFi network.'
          )
        end

        it 'raises a clear error when interactive sudo authentication fails' do
          err_stream = StringIO.new
          model = create_mac_os_test_model(err_stream: err_stream)
          allow(model).to receive_messages(
            wifi_interface:                             'en0',
            interactive_sudo_authentication_available?: true
          )
          allow(model).to receive(:run_command).with(
            sudo_check_command,
            raise_on_error:  false,
            timeout_in_secs: described_class::SUDO_AUTH_CHECK_TIMEOUT_SECONDS
          ).and_return(command_result(exitstatus: 1, stderr: 'sudo: a password is required'))
          expect(model).to receive(:system).with('sudo', '-v').and_return(false)
          expect(model).not_to receive(:run_command).with(
            %w[sudo networksetup -removepreferredwirelessnetwork en0 CafeNet],
            any_args
          )

          expect { model.remove_preferred_network('CafeNet') }
            .to raise_error(WifiWand::SudoAuthenticationError, /failed or was cancelled/)
          expect(err_stream.string).to include(
            'Administrator authentication is required to remove a saved WiFi network.'
          )
        end

        it 'treats a sudo cache-check timeout as missing authentication' do
          err_stream = StringIO.new
          model = create_mac_os_test_model(err_stream: err_stream)
          allow(model).to receive_messages(
            wifi_interface:                             'en0',
            interactive_sudo_authentication_available?: true
          )
          allow(model).to receive(:run_command).with(
            sudo_check_command,
            raise_on_error:  false,
            timeout_in_secs: described_class::SUDO_AUTH_CHECK_TIMEOUT_SECONDS
          ).and_raise(WifiWand::CommandTimeoutError.new(
            command:         sudo_check_command.join(' '),
            timeout_in_secs: described_class::SUDO_AUTH_CHECK_TIMEOUT_SECONDS
          ))
          allow(model).to receive(:run_command).with(
            %w[sudo networksetup -removepreferredwirelessnetwork en0 CafeNet],
            raise_on_error:  true,
            timeout_in_secs: described_class::SUDO_NETWORKSETUP_TIMEOUT_SECONDS
          ).and_return(success_result)
          expect(model).to receive(:system).with('sudo', '-v').and_return(true)

          expect(model.remove_preferred_network('CafeNet')).to eq(['CafeNet'])
          expect(err_stream.string).to include(
            'Administrator authentication is required to remove a saved WiFi network.'
          )
        end

        it 'returns false from the sudo cache check when sudo -n times out' do
          allow(model).to receive(:run_command).with(
            sudo_check_command,
            raise_on_error:  false,
            timeout_in_secs: described_class::SUDO_AUTH_CHECK_TIMEOUT_SECONDS
          ).and_raise(WifiWand::CommandTimeoutError.new(
            command:         sudo_check_command.join(' '),
            timeout_in_secs: described_class::SUDO_AUTH_CHECK_TIMEOUT_SECONDS
          ))

          expect(model.send(:sudo_authentication_cached?)).to be(false)
        end

        it 'detects interactive sudo authentication when stdin and stderr are TTYs' do
          stub_sudo_tty_streams

          expect(model.send(:interactive_sudo_authentication_available?)).to be(true)
        end

        it 'rejects interactive sudo authentication when stdin is not a TTY' do
          stub_sudo_tty_streams(stdin_tty: false)

          expect(model.send(:interactive_sudo_authentication_available?)).to be(false)
        end

        it 'rejects interactive sudo authentication when stderr is not a TTY' do
          stub_sudo_tty_streams(stderr_tty: false)

          expect(model.send(:interactive_sudo_authentication_available?)).to be(false)
        end

        it 'rejects interactive sudo authentication when stdin cannot report TTY status' do
          stub_sudo_tty_stream($stdin, responds_to_tty: false)

          expect(model.send(:interactive_sudo_authentication_available?)).to be(false)
          expect($stdin).not_to have_received(:tty?)
        end

        it 'rejects interactive sudo authentication when stderr cannot report TTY status' do
          stub_sudo_tty_stream($stdin, responds_to_tty: true)
          stub_sudo_tty_stream($stderr, responds_to_tty: false)

          expect(model.send(:interactive_sudo_authentication_available?)).to be(false)
          expect($stderr).not_to have_received(:tty?)
        end

        it 'fails clearly instead of prompting when sudo authentication is unavailable non-interactively' do
          allow(model).to receive_messages(
            wifi_interface:                             'en0',
            interactive_sudo_authentication_available?: false
          )
          allow(model).to receive(:run_command).with(
            sudo_check_command,
            raise_on_error:  false,
            timeout_in_secs: described_class::SUDO_AUTH_CHECK_TIMEOUT_SECONDS
          ).and_return(command_result(exitstatus: 1, stderr: 'sudo: a password is required'))
          expect(model).not_to receive(:system)
          expect(model).not_to receive(:run_command).with(
            %w[sudo networksetup -removepreferredwirelessnetwork en0 CafeNet],
            any_args
          )

          expect { model.remove_preferred_network('CafeNet') }
            .to raise_error(WifiWand::SudoAuthenticationError, /Run `sudo -v`/)
        end
      end

      describe '#probe_wifi_interface', :allow_real_probe_wifi_interface do
        subject(:model) { create_mac_os_test_model }

        let(:no_wifi_networksetup_output) do
          "Hardware Port: Ethernet\nDevice: en1\nEthernet Address: aa:bb:cc:dd:ee:ff\n"
        end
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
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .and_return(command_result(stdout: no_wifi_networksetup_output))
          expect(model).to receive(:run_command).with(
            %w[system_profiler -json SPNetworkDataType],
            raise_on_error:  true,
            timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
          ).and_return(command_result(stdout: system_profiler_output))

          expect(model.probe_wifi_interface).to eq('en0')
        end

        it 'caches the learned interface and service name from networksetup detection' do
          output = "Hardware Port: Wi-Fi\nDevice: en0\nEthernet Address: aa:bb:cc:dd:ee:ff\n"
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .and_return(command_result(stdout: output))
          expect(model).not_to receive(:run_command).with(
            %w[system_profiler -json SPNetworkDataType],
            any_args
          )

          expect(model.probe_wifi_interface).to eq('en0')
          expect(model.instance_variable_get(:@wifi_interface)).to eq('en0')
          expect(model.wifi_service_name).to eq('Wi-Fi')
        end

        it 'returns nil when WiFi service not found' do
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .and_return(command_result(stdout: no_wifi_networksetup_output))
          allow(model).to receive(:run_command)
            .with(
              %w[system_profiler -json SPNetworkDataType],
              raise_on_error:  true,
              timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
            )
            .and_return(command_result(stdout: '{"SPNetworkDataType": []}'))

          expect(model.probe_wifi_interface).to be_nil
        end

        it 'handles JSON parse errors gracefully' do
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .and_return(command_result(stdout: no_wifi_networksetup_output))
          allow(model).to receive(:run_command)
            .with(
              %w[system_profiler -json SPNetworkDataType],
              raise_on_error:  true,
              timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
            )
            .and_return(command_result(stdout: 'invalid json'))

          expect { model.probe_wifi_interface }.to raise_error(JSON::ParserError)
        end

        it 'uses system_profiler fallback without re-entering networksetup after failure' do
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .and_raise(os_command_error(exitstatus: 1, command: 'networksetup', text: 'boom'))
          expect(model).not_to receive(:wifi_service_name)
          allow(model).to receive(:run_command)
            .with(
              %w[system_profiler -json SPNetworkDataType],
              raise_on_error:  true,
              timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
            )
            .and_return(command_result(stdout: system_profiler_output))

          expect(model.probe_wifi_interface).to eq('en0')
        end

        it 'passes the remaining probe timeout into the system_profiler fallback' do
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: be_between(0, 0.5).inclusive) do
            sleep(0.01)
            raise WifiWand::CommandTimeoutError.new(command: 'networksetup', timeout_in_secs: 0.5)
          end
          expect(model).to receive(:run_command).with(
            %w[system_profiler -json SPNetworkDataType],
            raise_on_error:  true,
            timeout_in_secs: be_between(0, 0.5).exclusive
          ).and_return(command_result(stdout: system_profiler_output))

          expect(model.probe_wifi_interface(timeout_in_secs: 0.5)).to eq('en0')
        end
      end

      describe '#preferred_network_password' do
        it 'returns nil when the preferred network has no saved password' do
          model = create_mac_os_test_model
          ssid = 'TestNet'
          keychain_password_reader = instance_double(WifiWand::Platforms::Mac::KeychainPasswordReader)

          allow(model).to receive_messages(
            preferred_networks:       [ssid],
            keychain_password_reader: keychain_password_reader
          )
          allow(keychain_password_reader).to receive(:password_for)
            .with(ssid, timeout_in_secs: nil)
            .and_return(nil)

          expect(model.preferred_network_password(ssid)).to be_nil
        end

        it 'passes explicit keychain lookup timeouts through the facade' do
          model = create_mac_os_test_model
          ssid = 'TestNet'
          keychain_password_reader = instance_double(WifiWand::Platforms::Mac::KeychainPasswordReader)

          allow(model).to receive_messages(
            preferred_networks:       [ssid],
            keychain_password_reader: keychain_password_reader
          )
          allow(keychain_password_reader).to receive(:password_for)
            .with(ssid, timeout_in_secs: described_class::KEYCHAIN_LOOKUP_TIMEOUT_SECONDS)
            .and_return(nil)

          expect(model.preferred_network_password(ssid,
            timeout_in_secs: described_class::KEYCHAIN_LOOKUP_TIMEOUT_SECONDS)).to be_nil
        end
      end

      describe '#macos_version' do
        it 'handles version detection failure gracefully' do
          failing_model = create_mac_os_test_model
          allow(failing_model).to receive(:run_command).with(%w[sw_vers -productVersion])
            .and_raise(
              os_command_error(exitstatus: 1, command: 'sw_vers -productVersion', text: 'Command failed')
            )

          silence_output { expect(failing_model.macos_version).to be_nil }
        end
      end

      describe '#macos_version (real system)', :real_env_read_only, real_env_os: :os_mac do
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
            connected_network_name: 'TestNet'
          )
          allow(model).to receive(:_disconnect).and_return(nil)
          allow(model).to receive(:wait_until_disassociated!)
            .and_raise(wait_timeout_error(action: :disassociated, timeout: 5))

          expect { model.disconnect }
            .to raise_error(WifiWand::NetworkDisconnectionError, /still associated with 'TestNet'/)
        end

        it 'preserves a useful reason when association remains but no SSID is available' do
          allow(model).to receive_messages(
            wifi_on?:               true,
            connected?:             true,
            connected_network_name: nil
          )
          allow(model).to receive(:_disconnect).and_return(nil)
          allow(model).to receive(:wait_until_disassociated!)
            .and_raise(wait_timeout_error(action: :disassociated, timeout: 5))

          expect { model.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) { |error|
            expect(error.network_name).to be_nil
            expect(error.reason).to eq('interface remained associated')
          }
        end

        it 'preserves the network name when macOS disconnect commands fail' do
          transport = instance_double(WifiWand::Platforms::Mac::Helper::WifiTransport)
          allow(model).to receive_messages(
            wifi_on?:               true,
            connected_network_name: 'TestNet',
            wifi_transport:         transport
          )
          allow(model).to receive(:wait_until_disassociated!)
          allow(transport).to receive(:disconnect)
            .and_raise(os_command_error(
              exitstatus: 1,
              command:    'ifconfig disassociate fallback',
              text:       'ifconfig en0 disassociate exited with status 1: permission denied'
            ))

          expect { model.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
            expect(error.network_name).to eq('TestNet')
            expect(error.reason).to include('ifconfig disassociate fallback')
            expect(error.reason).to include('permission denied')
          end
          expect(model).not_to have_received(:wait_until_disassociated!)
        end

        it 'normalizes macOS disconnect timeouts as disconnection errors' do
          transport = instance_double(WifiWand::Platforms::Mac::Helper::WifiTransport)
          allow(model).to receive_messages(
            wifi_on?:               true,
            connected_network_name: 'TestNet',
            wifi_transport:         transport
          )
          allow(model).to receive(:wait_until_disassociated!)
          allow(transport).to receive(:disconnect)
            .and_raise(WifiWand::CommandTimeoutError.new(
              command:         'sudo ifconfig en0 disassociate',
              timeout_in_secs: WifiWand::Platforms::Mac::Helper::WifiTransport::SUDO_IFCONFIG_TIMEOUT_SECONDS
            ))

          expect { model.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
            expect(error.network_name).to eq('TestNet')
            expect(error.reason).to include('Command timed out after 5 seconds')
            expect(error.reason).to include('sudo ifconfig en0 disassociate')
          end
          expect(model).not_to have_received(:wait_until_disassociated!)
        end

        it 'normalizes macOS disconnect spawn failures as disconnection errors' do
          transport = instance_double(WifiWand::Platforms::Mac::Helper::WifiTransport)
          allow(model).to receive_messages(
            wifi_on?:               true,
            connected_network_name: 'TestNet',
            wifi_transport:         transport
          )
          allow(model).to receive(:wait_until_disassociated!)
          allow(transport).to receive(:disconnect)
            .and_raise(WifiWand::CommandSpawnError.new(
              command: 'ifconfig en0 disassociate',
              reason:  'Resource temporarily unavailable'
            ))

          expect { model.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
            expect(error.network_name).to eq('TestNet')
            expect(error.reason).to include('Could not start command')
            expect(error.reason).to include('ifconfig en0 disassociate')
            expect(error.reason).to include('Resource temporarily unavailable')
          end
          expect(model).not_to have_received(:wait_until_disassociated!)
        end

        it 'raises when disassociation is only transient during verification' do
          allow(model).to receive_messages(
            wifi_on?:                            true,
            connected_network_name:              'TestNet',
            disconnect_stability_window_in_secs: 0.1
          )
          allow(model).to receive_messages(_disconnect: nil, wait_until_disassociated!: nil,
            disassociated_stable?: false)

          expect { model.disconnect }
            .to raise_error(WifiWand::NetworkDisconnectionError, /still associated with 'TestNet'/)
        end

        it 'raises when swift fails, ifconfig fallback runs, and the interface remains associated' do
          swift_runtime = instance_double(WifiWand::Platforms::Mac::Helper::SwiftRuntime)
          allow(model).to receive_messages(
            wifi_on?:               true,
            connected_network_name: 'TestNet',
            swift_runtime:          swift_runtime,
            wifi_interface:         'en0'
          )
          allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(true)
          allow(swift_runtime).to receive(:disconnect)
            .and_raise(os_command_error(exitstatus: 1, command: 'swift disconnect', text: 'swift failure'))
          allow(model).to receive(:run_command).with(
            %w[sudo ifconfig en0 disassociate],
            raise_on_error:  false,
            timeout_in_secs: WifiWand::Platforms::Mac::Helper::WifiTransport::SUDO_IFCONFIG_TIMEOUT_SECONDS
          ).and_return(command_result(
            stdout:     '',
            stderr:     'sudo denied',
            exitstatus: 1,
            command:    'sudo ifconfig en0 disassociate'
          ))
          allow(model).to receive(:run_command).with(
            %w[ifconfig en0 disassociate],
            raise_on_error: false
          ).and_return(command_result(
            stdout:     '',
            stderr:     '',
            exitstatus: 0,
            command:    'ifconfig en0 disassociate'
          ))
          allow(model).to receive(:wait_until_disassociated!)
            .and_raise(wait_timeout_error(action: :disassociated, timeout: 5))

          expect { model.disconnect }
            .to raise_error(WifiWand::NetworkDisconnectionError, /still associated with 'TestNet'/)
        end

        it 'is a no-op when already disconnected' do
          allow(model).to receive_messages(
            wifi_on?:               true,
            connected?:             false,
            connected_network_name: nil
          )
          allow(model).to receive(:wait_until_disassociated!)
          allow(model).to receive(:run_command)
          expect(model).not_to receive(:wifi_transport)

          expect(model.disconnect).to be_nil
          expect(model).not_to have_received(:run_command)
          expect(model).not_to have_received(:wait_until_disassociated!)
        end
      end

      describe '#wifi_on' do
        it 'clears cached system_profiler WiFi data before and after turning WiFi on' do
          allow(model).to receive(:wifi_on?).and_return(false, true)
          allow(model).to receive(:wifi_interface).and_return('en0')

          expect(model).to receive(:invalidate_system_profiler_wifi_data_cache).ordered
          expect(model).to receive(:run_command)
            .with(['networksetup', '-setairportpower', 'en0', 'on'])
            .ordered
            .and_return(command_result(stdout: ''))
          expect(model).to receive(:invalidate_system_profiler_wifi_data_cache).ordered

          expect(model.wifi_on).to be_nil
        end
      end

      describe '#wifi_off' do
        it 'clears cached system_profiler WiFi data before and after turning WiFi off' do
          allow(model).to receive(:wifi_on?).and_return(true, false)
          allow(model).to receive(:wifi_interface).and_return('en0')

          expect(model).to receive(:invalidate_system_profiler_wifi_data_cache).ordered
          expect(model).to receive(:run_command)
            .with(['networksetup', '-setairportpower', 'en0', 'off'])
            .ordered
            .and_return(command_result(stdout: ''))
          expect(model).to receive(:invalidate_system_profiler_wifi_data_cache).ordered

          expect(model.wifi_off).to be_nil
        end
      end

      describe '#_disconnect' do
        it 'clears cached system_profiler WiFi data before and after delegating disconnect orchestration' do
          transport = instance_double(WifiWand::Platforms::Mac::Helper::WifiTransport, disconnect: nil)
          allow(model).to receive(:wifi_transport).and_return(transport)

          expect(model).to receive(:invalidate_system_profiler_wifi_data_cache).ordered
          expect(transport).to receive(:disconnect).ordered
          expect(model).to receive(:invalidate_system_profiler_wifi_data_cache).ordered

          expect(model._disconnect).to be_nil
        end
      end

      describe '#validate_os_preconditions' do
        it 'returns :ok without warming the Swift mutation runtime' do
          verbose_model = create_mac_os_test_model(verbose: true, out_stream: StringIO.new)
          swift_runtime = instance_double(WifiWand::Platforms::Mac::Helper::SwiftRuntime)
          allow(verbose_model).to receive(:swift_runtime).and_return(swift_runtime)

          expect(swift_runtime).not_to receive(:swift_and_corewlan_present?)
          expect(verbose_model.validate_os_preconditions).to eq(:ok)
          expect(verbose_model.out_stream.string).to eq('')
        end
      end

      describe '#preferred_networks' do
        it 'parses and sorts preferred networks correctly' do
          networksetup_output = "Preferred networks on en0:\n\tLibraryWiFi\n\t@thePAD/Magma\n\tHomeNetwork\n"
          allow(model).to receive_messages(
            wifi_interface: 'en0',
            run_command:    command_result(stdout: networksetup_output)
          )

          result = model.preferred_networks
          # Sorted alphabetically, case insensitive
          expect(result).to eq(['@thePAD/Magma', 'HomeNetwork', 'LibraryWiFi'])
        end

        it 'handles empty preferred networks list' do
          allow(model).to receive_messages(
            wifi_interface: 'en0',
            run_command:    command_result(stdout: "Preferred networks on en0:\n")
          )

          expect(model.preferred_networks).to eq([])
        end
      end

      describe '#_available_network_names' do
        let(:network_scanner) { instance_double(WifiWand::Platforms::Mac::NetworkScanner) }

        before do
          model.instance_variable_set(:@network_scanner, network_scanner)
        end

        it 'delegates to the network scanner' do
          expect(network_scanner).to receive(:available_network_names).and_return(['Cafe WiFi'])

          expect(model._available_network_names).to eq(['Cafe WiFi'])
        end
      end

      describe '#available_network_scan' do
        let(:network_scanner) { instance_double(WifiWand::Platforms::Mac::NetworkScanner) }

        before do
          model.instance_variable_set(:@network_scanner, network_scanner)
        end

        it 'keeps the public WiFi power guard before delegating' do
          allow(model).to receive(:wifi_on?).and_return(false)

          expect(network_scanner).not_to receive(:scan)
          expect { model.available_network_scan }.to raise_error(WifiWand::WifiOffError)
        end

        it 'delegates to the network scanner when WiFi is on' do
          scan = {
            'networks'          => ['Cafe WiFi'],
            'scan_status'       => 'ok',
            'scan_source'       => 'mac_helper',
            'ssid_data_trusted' => true,
            'warning'           => nil,
          }
          allow(model).to receive(:wifi_on?).and_return(true)
          expect(network_scanner).to receive(:scan).and_return(scan)

          expect(model.available_network_scan).to eq(scan)
        end
      end

      describe '#_connect' do
        it 'clears cached system_profiler WiFi data before and after delegating connect orchestration' do
          transport = instance_double(WifiWand::Platforms::Mac::Helper::WifiTransport)
          allow(model).to receive(:wifi_transport).and_return(transport)

          expect(model).to receive(:invalidate_system_profiler_wifi_data_cache).ordered
          expect(transport).to receive(:connect).with('TestNetwork', 'password').ordered
          expect(model).to receive(:invalidate_system_profiler_wifi_data_cache).ordered

          model._connect('TestNetwork', 'password')
        end
      end

      describe '#connection_security_type' do
        let(:network_name) { 'TestNetwork' }
        let(:wifi_interface) { 'en0' }
        let(:connected_system_profiler_wifi_data) do
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
          # Stub wifi_on? so connected-network reads do not attempt a real OS command.
          allow(model).to receive_messages(
            _connected_network_name: network_name,
            wifi_interface:          wifi_interface,
            wifi_on?:                true
          )
        end

        # When connected, system_profiler moves the current SSID to
        # 'spairport_airport_other_local_wireless_networks'. The tests below mirror
        # that layout so they match the navigator's associated-network list selection.
        [
          ['WPA2', 'WPA2'],
          ['WPA3', 'WPA3'],
          ['WPA', 'WPA'],
          ['WPA1', 'WPA'],
          ['WEP', 'WEP'],
          ['spairport_security_mode_none', 'NONE'],
          ['None', 'NONE'],
          ['OWE', 'NONE'],
          ['', 'NONE'],
          ['Unknown Security', nil],
        ].each do |security_mode, expected_result|
          mode_description = security_mode.empty? ? 'blank security mode' : security_mode

          it "returns #{expected_result || 'nil'} for #{mode_description}" do
            system_profiler_wifi_data = {
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

            allow(model).to receive(:system_profiler_wifi_data).and_return(system_profiler_wifi_data)

            expect(model.connection_security_type).to eq(expected_result)
          end
        end

        # Regression: the original code hardcoded 'spairport_airport_local_wireless_networks',
        # which is the wrong key when connected. system_profiler places the current SSID under
        # 'spairport_airport_other_local_wireless_networks' once the interface is associated.
        it 'finds the connected network under other_local_wireless_networks (not local)' do
          system_profiler_wifi_data = {
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

          allow(model).to receive(:system_profiler_wifi_data).and_return(system_profiler_wifi_data)

          expect(model.connection_security_type).to eq('WPA2')
        end

        it 'uses one system_profiler WiFi snapshot while resolving security for a single lookup' do
          helper_double = instance_double(WifiWand::Platforms::Mac::Helper::Client)
          json_output = JSON.generate(connected_system_profiler_wifi_data)
          helper_result = helper_query_result.new(payload: nil)

          allow(model).to receive(:_connected_network_name).and_call_original
          allow(model).to receive(:helper_client).and_return(helper_double)
          stub_fast_network_identity_missing
          allow(helper_double).to receive(:connected_network_name).and_return(helper_result)

          expect(model).to receive(:run_command).with(
            %w[system_profiler -json SPAirPortDataType],
            raise_on_error:  true,
            timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
          ).once.and_return(command_result(stdout: json_output))

          expect(model.connection_security_type).to eq('WPA2')
        end

        it 'refreshes system_profiler WiFi data between separate security lookups' do
          helper_double = instance_double(WifiWand::Platforms::Mac::Helper::Client)
          helper_result = helper_query_result.new(payload: nil)
          first_system_profiler_wifi_data = JSON.generate(
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
          second_system_profiler_wifi_data = JSON.generate(
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
          allow(model).to receive(:helper_client).and_return(helper_double)
          stub_fast_network_identity_missing
          allow(helper_double).to receive(:connected_network_name).and_return(helper_result)

          expect(model).to receive(:run_command).with(
            %w[system_profiler -json SPAirPortDataType],
            raise_on_error:  true,
            timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
          ).twice.and_return(
            command_result(stdout: first_system_profiler_wifi_data),
            command_result(stdout: second_system_profiler_wifi_data)
          )

          expect(model.connection_security_type).to eq('WPA2')
          expect(model.connection_security_type).to eq('WPA3')
        end

        it 'clears cached system_profiler WiFi data before a state-changing operation' do
          json_output = JSON.generate(connected_system_profiler_wifi_data)

          expect(model).to receive(:run_command).with(
            %w[system_profiler -json SPAirPortDataType],
            raise_on_error:  true,
            timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
          ).twice.and_return(command_result(stdout: json_output))
          allow(model).to receive(:wifi_interface).and_return(wifi_interface)
          allow(model).to receive(:run_command).with(
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

        it 'returns nil when system_profiler WiFi data is unavailable' do
          allow(model).to receive(:system_profiler_wifi_data).and_return({})

          expect(model.connection_security_type).to be_nil
        end

        it 'returns nil when wifi interface not found in system_profiler WiFi data' do
          system_profiler_wifi_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                           => 'other_interface',
                'spairport_airport_other_local_wireless_networks' => [],
              }],
            }],
          }

          allow(model).to receive(:system_profiler_wifi_data).and_return(system_profiler_wifi_data)

          expect(model.connection_security_type).to be_nil
        end

        it 'returns nil when connected network not found in scan results' do
          system_profiler_wifi_data = {
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

          allow(model).to receive(:system_profiler_wifi_data).and_return(system_profiler_wifi_data)

          expect(model.connection_security_type).to be_nil
        end

        it 'returns nil when security mode information is missing' do
          system_profiler_wifi_data = {
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

          allow(model).to receive(:system_profiler_wifi_data).and_return(system_profiler_wifi_data)

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
          system_profiler_wifi_data = {
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

          allow(model).to receive_messages(system_profiler_wifi_data: system_profiler_wifi_data,
            connected_network_name: network_name)

          expect(model.network_hidden?).to be false
        end

        it 'returns true when connected network is not in broadcast list (hidden)' do
          system_profiler_wifi_data = {
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

          allow(model).to receive_messages(system_profiler_wifi_data: system_profiler_wifi_data,
            connected_network_name: network_name)

          expect(model.network_hidden?).to be true
        end

        it 'returns false when connected visible network appears only in other_local_wireless_networks' do
          system_profiler_wifi_data = {
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
            system_profiler_wifi_data: system_profiler_wifi_data,
            connected_network_name:    network_name,
            wifi_on?:                  true
          )

          expect(model.network_hidden?).to be false
        end

        it 'uses provided system_profiler WiFi data instead of re-querying the connected network name' do
          system_profiler_wifi_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                           => wifi_interface,
                'spairport_current_network_information'           => {
                  '_name' => network_name,
                },
                'spairport_airport_other_local_wireless_networks' => [{
                  '_name'                  => network_name,
                  'spairport_signal_noise' => '50/10',
                }],
              }],
            }],
          }

          allow(model).to receive(:system_profiler_wifi_data).and_return(system_profiler_wifi_data)
          allow(model).to receive(:connected_network_name).and_raise(
            WifiWand::MacOsRedactionError.new(operation_description: 'current WiFi network queries')
          )

          expect(model.network_hidden?).to be false
        end

        it 'returns false when not connected to any network' do
          allow(model).to receive(:_connected_network_name).and_return(nil)

          expect(model.network_hidden?).to be false
        end

        it 'returns false when system_profiler WiFi data is unavailable' do
          allow(model).to receive(:system_profiler_wifi_data).and_return({})

          expect(model.network_hidden?).to be false
        end

        it 'returns false when wifi interface not found in system_profiler WiFi data' do
          system_profiler_wifi_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name'                                 => 'other_interface',
                'spairport_current_network_information' => {
                  '_name' => network_name,
                },
              }],
            }],
          }

          allow(model).to receive(:system_profiler_wifi_data).and_return(system_profiler_wifi_data)

          expect(model.network_hidden?).to be false
        end

        it 'returns false when current network information is missing' do
          system_profiler_wifi_data = {
            'SPAirPortDataType' => [{
              'spairport_airport_interfaces' => [{
                '_name' => wifi_interface,
                # No spairport_current_network_information
              }],
            }],
          }

          allow(model).to receive(:system_profiler_wifi_data).and_return(system_profiler_wifi_data)

          expect(model.network_hidden?).to be false
        end
      end

      describe '#wifi_service_name edge cases' do
        it 'returns Wi-Fi as final fallback when all detection fails' do
          no_wifi_output = "Hardware Port: Ethernet\nDevice: en1"
          allow(model).to receive(:run_command)
            .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
            .and_return(command_result(stdout: no_wifi_output))
          allow(model).to receive(:wifi_interface).and_return('en0')

          result = model.wifi_service_name
          expect(result).to eq('Wi-Fi')
        end
      end
    end

    describe '#create_model with provided interface' do
      context 'when valid wifi_interface is provided' do
        it 'uses the provided interface without probing for another interface',
          :real_env_read_only, real_env_os: :os_mac do
          model = described_class.create_model(wifi_interface: 'en0')
          expect(model.wifi_interface).to eq('en0')
        end
      end

      context 'when invalid wifi_interface is provided' do
        it 'raises InvalidInterfaceError' do
          model = described_class.new(wifi_interface: 'invalid0')
          allow(model).to receive(:is_wifi_interface?).with('invalid0').and_return(false)
          allow(described_class).to receive(:new).and_return(model)

          expect { described_class.create_model(wifi_interface: 'invalid0') }
            .to raise_error(WifiWand::InvalidInterfaceError)
        end
      end

      context 'when no wifi_interface is provided' do
        it 'defers interface discovery until wifi_interface is requested' do
          model = described_class.create_model
          expect(model.instance_variable_get(:@wifi_interface)).to be_nil
        end
      end
    end
  end
end
