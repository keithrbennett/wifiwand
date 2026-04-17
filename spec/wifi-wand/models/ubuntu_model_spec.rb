# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/models/ubuntu_model'

module WifiWand
  describe UbuntuModel do
    let(:subject) { create_ubuntu_test_model }

    # Mock network connectivity tester to prevent real network calls during mocked tests
    before do
      unless uses_real_env?
        tester = WifiWand::NetworkConnectivityTester
        allow_any_instance_of(tester).to receive(:internet_connectivity_state).and_return(:reachable)
        allow_any_instance_of(tester).to receive(:tcp_connectivity?).and_return(true)
        allow_any_instance_of(tester).to receive(:dns_working?).and_return(true)

        # Mock OS command execution to prevent real WiFi control commands
        allow(subject).to receive_messages(run_os_command: command_result(stdout: ''), till: nil)
      end
    end



    # Constants for common patterns
    WIFI_INTERFACE_REGEX = /wl[a-z0-9]+/
    NMCLI_RADIO_CMD = 'nmcli radio wifi'

    # Mocked tests with proper stubbing
    context 'when running core functionality tests' do
      describe '#wifi_on and #wifi_off failure paths' do
        it 'raises WifiEnableError when WiFi remains disabled after enable attempt' do
          allow(subject).to receive(:wifi_on?).and_return(false, false)
          allow(subject).to receive(:run_os_command).with(%w[nmcli radio wifi on])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:till).with(:wifi_on, timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT).and_return(nil)

          expect { subject.wifi_on }.to raise_error(WifiWand::WifiEnableError)
        end

        it 'raises WifiDisableError when WiFi remains enabled after disable attempt' do
          allow(subject).to receive(:wifi_on?).and_return(true, true)
          allow(subject).to receive(:run_os_command).with(%w[nmcli radio wifi off])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:till).with(:wifi_off, timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT).and_return(nil)

          expect { subject.wifi_off }.to raise_error(WifiWand::WifiDisableError)
        end
      end

      describe '#_connect early return and branches' do
        # Helper method to set up common _connect test mocking
        def setup_connect_test(connected_network: nil, profile_name: nil, old_password: nil,
          security_param: nil)
          allow(subject).to receive(:_connected_network_name).and_return(connected_network)
          if profile_name
            allow(subject).to receive(:find_best_profile_for_ssid).and_return(profile_name)
            allow(subject).to receive(:_preferred_network_password).and_return(old_password) if old_password
            allow(subject).to receive(:get_security_parameter).and_return(security_param) if security_param
          else
            allow(subject).to receive(:find_best_profile_for_ssid).and_return(nil)
          end
        end

        it 'returns immediately when already connected to target network' do
          allow(subject).to receive(:connected?).and_return(true)
          setup_connect_test(connected_network: 'NetA')
          expect(subject).not_to receive(:run_os_command)
          expect { subject._connect('NetA') }.not_to raise_error
        end

        it 'does not return early when SSID matches but NetworkManager is not fully connected' do
          allow(subject).to receive(:connected?).and_return(false)
          setup_connect_test(connected_network: 'NetA', profile_name: 'NetA')

          expect(subject).to receive(:run_os_command).with(%w[nmcli connection up NetA])
            .and_return(command_result(stdout: ''))
          expect { subject._connect('NetA') }.not_to raise_error
        end

        it 'modifies existing profile when password changed and security is known' do
          setup_connect_test(profile_name: 'SSID1', old_password: 'oldpass',
            security_param: '802-11-wireless-security.psk')

          expect(subject).to receive(:run_os_command)
            .with(%w[nmcli connection modify SSID1 802-11-wireless-security.psk newpass])
            .and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command).with(%w[nmcli connection up SSID1])
            .and_return(command_result(stdout: ''))
          expect { subject._connect('SSID1', 'newpass') }.not_to raise_error
        end

        it 'falls back to direct connect when security cannot be determined' do
          setup_connect_test(profile_name: 'SSID2', old_password: 'oldpass', security_param: nil)

          expect(subject).to receive(:run_os_command).with(%w[nmcli dev wifi connect SSID2 password newpass])
            .and_return(command_result(stdout: ''))
          expect { subject._connect('SSID2', 'newpass') }.not_to raise_error
        end

        it 'brings up existing profile when connecting without password' do
          setup_connect_test(profile_name: 'SSID3')

          expect(subject).to receive(:run_os_command).with(%w[nmcli connection up SSID3])
            .and_return(command_result(stdout: ''))
          expect { subject._connect('SSID3') }.not_to raise_error
        end

        it 'raises NetworkNotFoundError when network not in range' do
          setup_connect_test

          expect(subject).to receive(:run_os_command).with(%w[nmcli dev wifi connect SSID4 password pw])
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(10, 'nmcli dev wifi connect',
              'Error: No network with SSID \'SSID4\' found'))

          expect { subject._connect('SSID4', 'pw') }
            .to raise_error(WifiWand::NetworkNotFoundError, /SSID4/)
        end

        it 'raises NetworkAuthenticationError when password is wrong (secrets required)' do
          setup_connect_test

          expect(subject).to receive(:run_os_command)
            .with(%w[nmcli dev wifi connect SecureNet password wrongpass])
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(4, 'nmcli dev wifi connect',
              'Error: Connection activation failed: Secrets were required, but not provided'))

          expect { subject._connect('SecureNet', 'wrongpass') }
            .to raise_error(WifiWand::NetworkAuthenticationError, /SecureNet/)
        end

        it 'raises NetworkAuthenticationError when authentication fails' do
          setup_connect_test

          expect(subject).to receive(:run_os_command)
            .with(%w[nmcli dev wifi connect SecureNet password badpass])
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(4, 'nmcli dev wifi connect',
              'Error: Connection activation failed: (53) authentication failed'))

          expect { subject._connect('SecureNet', 'badpass') }
            .to raise_error(WifiWand::NetworkAuthenticationError, /SecureNet/)
        end

        it 'raises NetworkAuthenticationError for error code 7 (secrets issue)' do
          setup_connect_test

          expect(subject).to receive(:run_os_command)
            .with(%w[nmcli dev wifi connect SecureNet password invalid])
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(7, 'nmcli dev wifi connect',
              'Error: Connection activation failed: (7) No secrets provided'))

          expect { subject._connect('SecureNet', 'invalid') }
            .to raise_error(WifiWand::NetworkAuthenticationError, /SecureNet/)
        end

        it 'raises WifiInterfaceError when no suitable device found' do
          setup_connect_test
          allow(subject).to receive(:wifi_interface).and_return('wlan0')

          expect(subject).to receive(:run_os_command)
            .with(%w[nmcli dev wifi connect SSID5])
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(
              5, 'nmcli dev wifi connect', 'Error: No suitable device found'))

          expect { subject._connect('SSID5') }.to raise_error(WifiWand::WifiInterfaceError)
        end

        it 'raises NetworkConnectionError for generic activation failures (out of range)' do
          setup_connect_test

          expect(subject).to receive(:run_os_command).with(%w[nmcli dev wifi connect WeakSignal])
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(4, 'nmcli dev wifi connect',
              'Error: Connection activation failed'))

          expect { subject._connect('WeakSignal') }
            .to raise_error(WifiWand::NetworkConnectionError, /out of range/)
        end

        it 're-raises unknown errors from nmcli' do
          setup_connect_test

          expect(subject).to receive(:run_os_command).with(%w[nmcli dev wifi connect SSID6 password pw])
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(2, 'nmcli dev wifi connect',
              'Unknown system failure'))

          expect { subject._connect('SSID6', 'pw') }
            .to raise_error(WifiWand::CommandExecutor::OsCommandError, /Unknown system failure/)
        end
      end

      describe '#get_security_parameter and #security_parameter' do
        it 'returns nil when nmcli scan fails' do
          expect(subject).to receive(:run_os_command).with(%w[nmcli -t -f SSID,SECURITY dev wifi list], false)
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(1, 'nmcli', 'scan failed'))
          expect(subject.send(:get_security_parameter, 'Any')).to be_nil
        end

        it 'returns nil for unsupported/enterprise/open security types' do
          expect(subject).to receive(:run_os_command).with(%w[nmcli -t -f SSID,SECURITY dev wifi list], false)
            .and_return(command_result(stdout: 'CorpNet:802.1X'))
          expect(subject.send(:get_security_parameter, 'CorpNet')).to be_nil
        end

        it 'delegates via #security_parameter and returns PSK param for WPA2' do
          expect(subject).to receive(:run_os_command).with(%w[nmcli -t -f SSID,SECURITY dev wifi list], false)
            .and_return(command_result(stdout: 'HomeNet:WPA2'))
          expect(subject.send(:security_parameter, 'HomeNet')).to eq('802-11-wireless-security.psk')
        end
      end

      describe '#find_best_profile_for_ssid' do
        it 'returns nil when listing connections fails' do
          expect(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f NAME,TIMESTAMP connection show], false)
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(1, 'nmcli', 'Error'))
          expect(subject.send(:find_best_profile_for_ssid, 'SSID')).to be_nil
        end

        it 'prefers the most recent duplicate profile over an older exact-name profile' do
          expect(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f NAME,TIMESTAMP connection show], false)
            .and_return(command_result(stdout: "MySSID:100\nMySSID 1:300\nMySSID 2:200\nOtherSSID:999"))

          expect(subject.send(:find_best_profile_for_ssid, 'MySSID')).to eq('MySSID 1')
        end
      end

      describe '#remove_preferred_network' do
        it 'returns an empty array without deleting when network not present' do
          allow(subject).to receive(:preferred_networks).and_return(%w[A B])
          expect(subject).not_to receive(:run_os_command).with(/nmcli connection delete/)

          expect(subject.remove_preferred_network('C')).to eq([])
        end

        it 'deletes an existing preferred network and returns the deleted profile name' do
          allow(subject).to receive(:preferred_networks).and_return(['Home'])
          expect(subject).to receive(:run_os_command).with(%w[nmcli connection delete Home])

          expect(subject.remove_preferred_network('Home')).to eq(['Home'])
        end

        it 'deletes duplicate NetworkManager profiles for an SSID without touching unrelated profiles' do
          allow(subject).to receive(:preferred_networks)
            .and_return(['MySSID', 'MySSID 1', 'MySSID 2', 'MySSIDGuest'])
          expect(subject).to receive(:run_os_command)
            .with(%w[nmcli connection delete MySSID]).ordered
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'delete', 'MySSID 1']).ordered
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'delete', 'MySSID 2']).ordered

          expect(subject.remove_preferred_network('MySSID')).to eq(['MySSID', 'MySSID 1', 'MySSID 2'])
        end

        it 'treats duplicate NetworkManager profiles as saved for has_preferred_network?' do
          allow(subject).to receive(:preferred_networks).and_return(['MySSID 1', 'MySSID 2'])

          expect(subject.has_preferred_network?('MySSID')).to be(true)
          expect(subject.has_preferred_network?('OtherSSID')).to be(false)
        end

        it 'uses the saved password from the most recent matching profile' do
          allow(subject).to receive(:preferred_networks).and_return(['MySSID', 'MySSID 1'])
          expect(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f NAME,TIMESTAMP connection show], false)
            .and_return(command_result(stdout: "MySSID:100\nMySSID 1:300"))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', '--show-secrets', 'connection', 'show', 'MySSID 1'], false)
            .and_return(command_result(stdout: '802-11-wireless-security.psk:    fresh-secret'))

          expect(subject.preferred_network_password('MySSID')).to eq('fresh-secret')
        end

        it 'uses the saved WEP key from the most recent matching profile' do
          allow(subject).to receive(:preferred_networks).and_return(['MySSID', 'MySSID 1'])
          expect(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f NAME,TIMESTAMP connection show], false)
            .and_return(command_result(stdout: "MySSID:100\nMySSID 1:300"))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', '--show-secrets', 'connection', 'show', 'MySSID 1'], false)
            .and_return(command_result(stdout: '802-11-wireless-security.wep-key0:    fresh-wep-key'))

          expect(subject.preferred_network_password('MySSID')).to eq('fresh-wep-key')
        end

        it 'preserves exact duplicate profile name lookups' do
          allow(subject).to receive(:preferred_networks).and_return(['MySSID', 'MySSID 1'])
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', '--show-secrets', 'connection', 'show', 'MySSID 1'], false)
            .and_return(command_result(stdout: '802-11-wireless-security.psk:    duplicate-secret'))

          expect(subject.preferred_network_password('MySSID 1')).to eq('duplicate-secret')
        end

        it 'does not delete non-Wi-Fi profile even if name matches' do
          allow(subject).to receive(:preferred_networks).and_return(['MyWifiNetwork'])
          expect(subject).not_to receive(:run_os_command).with(/nmcli connection delete/)

          expect(subject.remove_preferred_network('Wired connection 1')).to eq([])
        end
      end

      describe 'saved password connect flow' do
        it 'passes the saved password from the best matching profile into _connect' do
          allow(subject).to receive(:wifi_on)
          allow(subject.connection_manager).to receive(:wait_for_connection_activation)
          allow(subject).to receive(:connection_ready?).and_return(false, true)
          allow(subject).to receive(:connected_network_name).and_return(nil, 'MySSID')
          allow(subject).to receive(:preferred_networks).and_return(['MySSID', 'MySSID 1'])
          expect(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f NAME,TIMESTAMP connection show], false)
            .and_return(command_result(stdout: "MySSID:100\nMySSID 1:300"))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', '--show-secrets', 'connection', 'show', 'MySSID 1'], false)
            .and_return(command_result(stdout: '802-11-wireless-security.psk:    fresh-secret'))
          expect(subject).to receive(:_connect).with('MySSID', 'fresh-secret')

          subject.connect('MySSID')
          expect(subject.last_connection_used_saved_password?).to be true
        end

        it 'passes the saved WEP key from the best matching profile into _connect' do
          allow(subject).to receive(:wifi_on)
          allow(subject.connection_manager).to receive(:wait_for_connection_activation)
          allow(subject).to receive(:connection_ready?).and_return(false, true)
          allow(subject).to receive(:connected_network_name).and_return(nil, 'MySSID')
          allow(subject).to receive(:preferred_networks).and_return(['MySSID', 'MySSID 1'])
          expect(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f NAME,TIMESTAMP connection show], false)
            .and_return(command_result(stdout: "MySSID:100\nMySSID 1:300"))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', '--show-secrets', 'connection', 'show', 'MySSID 1'], false)
            .and_return(command_result(stdout: '802-11-wireless-security.wep-key0:    fresh-wep-key'))
          expect(subject).to receive(:_connect).with('MySSID', 'fresh-wep-key')

          subject.connect('MySSID')
          expect(subject.last_connection_used_saved_password?).to be true
        end
      end

      describe '#_disconnect' do
        it 'returns nil when disconnect succeeds' do
          allow(subject).to receive(:wifi_interface).and_return('wlan0')
          expect(subject).to receive(:run_os_command).with(%w[nmcli dev disconnect wlan0])
            .and_return(command_result(stdout: ''))
          expect(subject.send(:_disconnect)).to be_nil
        end
      end

      describe '#nameservers with active connection' do
        it 'returns connection-specific nameservers when present' do
          allow(subject).to receive_messages(
            active_connection_profile_name: 'Conn1',
            _connected_network_name:        'SSID-Conn1'
          )
          expect(subject).to receive(:nameservers_from_connection).with('Conn1').and_return(['1.1.1.1'])
          expect(subject.nameservers).to eq(['1.1.1.1'])
        end

        it 'prefers the active profile name over the SSID when resolving DNS' do
          allow(subject).to receive_messages(
            active_connection_profile_name: 'RenamedProfile',
            _connected_network_name:        'SSID-RenamedProfile'
          )
          expect(subject).to receive(:nameservers_from_connection).with('RenamedProfile')
            .and_return(['9.9.9.9'])
          expect(subject.nameservers).to eq(['9.9.9.9'])
        end

        it 'falls back to resolv.conf when connection has no DNS' do
          allow(subject).to receive(:active_connection_profile_name).and_return('Conn2')
          expect(subject).to receive(:nameservers_from_connection).with('Conn2').and_return([])
          expect(subject).to receive(:nameservers_using_resolv_conf).and_return(['9.9.9.9'])
          expect(subject.nameservers).to eq(['9.9.9.9'])
        end

        it 'uses SSID as a fallback when profile name is unavailable' do
          allow(subject).to receive_messages(
            active_connection_profile_name: nil,
            _connected_network_name:        'FallbackSSID'
          )
          expect(subject).to receive(:nameservers_from_connection).with('FallbackSSID')
            .and_return(['4.4.4.4'])
          expect(subject.nameservers).to eq(['4.4.4.4'])
        end
      end

      describe '#open_resource' do
        it 'invokes xdg-open on the given URL' do
          expect(subject).to receive(:run_os_command).with(['xdg-open', 'https://example.com'])
            .and_return(command_result(stdout: ''))
          subject.open_resource('https://example.com')
        end
      end

      describe '#default_interface' do
        it 'returns nil when ip route command fails' do
          expect(subject).to receive(:run_os_command).with(%w[ip route show default], false)
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(1, 'ip route show default', 'failed'))
          expect(subject.default_interface).to be_nil
        end
      end

      describe '#nameservers_from_connection' do
        it 'parses DNS servers from nmcli connection output' do
          nmcli_output = <<~OUT
            connection.id:                   ConnX
            ipv4.dns[1]:                     1.1.1.1
            IP4.DNS[2]:                      9.9.9.9
            some.other:                      value
          OUT
          expect(subject).to receive(:run_os_command).with(%w[nmcli connection show ConnX], false)
            .and_return(command_result(stdout: nmcli_output))
          expect(subject.send(:nameservers_from_connection, 'ConnX')).to eq(['1.1.1.1', '9.9.9.9'])
        end

        it 'returns empty array when nmcli connection show fails' do
          expect(subject).to receive(:run_os_command).with(%w[nmcli connection show ConnY], false)
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(1, 'nmcli connection show', 'failed'))
          expect(subject.send(:nameservers_from_connection, 'ConnY')).to eq([])
        end

        it 'parses IPv6 DNS servers without truncating at colons' do
          nmcli_output = <<~OUT
            connection.id:                   ConnZ
            ipv6.dns[1]:                     2606:4700:4700::1111
            IP6.DNS[2]:                      2606:4700:4700::1001
            some.other:                      value
          OUT
          expect(subject).to receive(:run_os_command).with(%w[nmcli connection show ConnZ], false)
            .and_return(command_result(stdout: nmcli_output))
          expect(subject.send(:nameservers_from_connection, 'ConnZ'))
            .to eq(['2606:4700:4700::1111', '2606:4700:4700::1001'])
        end

        it 'parses mixed IPv4 and IPv6 DNS servers' do
          nmcli_output = <<~OUT
            connection.id:                   ConnM
            ipv4.dns[1]:                     1.1.1.1
            IP4.DNS[2]:                      9.9.9.9
            ipv6.dns[1]:                     2606:4700:4700::1111
            IP6.DNS[2]:                      2001:4860:4860::8888
          OUT
          expect(subject).to receive(:run_os_command).with(%w[nmcli connection show ConnM], false)
            .and_return(command_result(stdout: nmcli_output))
          result = subject.send(:nameservers_from_connection, 'ConnM')
          expect(result).to include('1.1.1.1', '9.9.9.9', '2606:4700:4700::1111', '2001:4860:4860::8888')
          expect(result.length).to eq(4)
        end
      end

      describe '#validate_os_preconditions' do
        it 'returns :ok when all required commands are available' do
          allow(subject).to receive(:command_available?).with('iw').and_return(command_result(stdout: true))
          allow(subject).to receive(:command_available?).with('nmcli').and_return(true)

          expect(subject.validate_os_preconditions).to eq(:ok)
        end

        it 'raises CommandNotFoundError when iw is missing' do
          allow(subject).to receive(:command_available?).with('iw').and_return(false)
          allow(subject).to receive(:command_available?).with('nmcli').and_return(true)

          expect { subject.validate_os_preconditions }
            .to raise_error(WifiWand::CommandNotFoundError, /iw.*install.*sudo apt install iw/)
        end

        it 'raises CommandNotFoundError when nmcli is missing' do
          allow(subject).to receive(:command_available?).with('iw').and_return(true)
          allow(subject).to receive(:command_available?).with('nmcli').and_return(false)

          expect { subject.validate_os_preconditions }
            .to raise_error(WifiWand::CommandNotFoundError,
              /nmcli.*install.*sudo apt install network-manager/)
        end

        it 'raises CommandNotFoundError when both commands are missing' do
          allow(subject).to receive(:command_available?).with('iw').and_return(false)
          allow(subject).to receive(:command_available?).with('nmcli').and_return(false)

          expect { subject.validate_os_preconditions }
            .to raise_error(WifiWand::CommandNotFoundError, /iw.*nmcli/)
        end
      end

      describe '#probe_wifi_interface' do
        it 'returns first managed wireless interface from iw dev output' do
          iw_output = <<~IW_OUTPUT
            phy#0
                Interface wlp3s0
                type managed
            phy#1
                Interface wlan1
                type managed
          IW_OUTPUT

          allow(subject).to receive(:run_os_command)
            .with(%w[iw dev])
            .and_return(command_result(stdout: iw_output))

          expect(subject.probe_wifi_interface).to eq('wlp3s0')
        end

        it 'skips p2p-dev virtual interface and returns the managed interface' do
          iw_output = <<~IW_OUTPUT
            phy#0
                Interface p2p-dev-wlp3s0
                type P2P-device
                Interface wlp3s0
                type managed
          IW_OUTPUT

          allow(subject).to receive(:run_os_command)
            .with(%w[iw dev])
            .and_return(command_result(stdout: iw_output))

          expect(subject.probe_wifi_interface).to eq('wlp3s0')
        end

        it 'returns nil when no managed interfaces found' do
          allow(subject).to receive(:run_os_command)
            .with(%w[iw dev])
            .and_return(command_result(stdout: "phy#0\n    type managed"))

          expect(subject.probe_wifi_interface).to be_nil
        end

        it 'handles command failures gracefully' do
          allow(subject).to receive(:run_os_command)
            .with(%w[iw dev])
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(1, 'iw dev', 'Command failed'))

          expect { subject.probe_wifi_interface }
            .to raise_error(WifiWand::CommandExecutor::OsCommandError)
        end
      end

      describe '#preferred_networks' do
        it 'returns list of saved Wi-Fi network profiles' do
          nmcli_output = <<~OUT.chomp
            TestNetwork-1:802-11-wireless
            TestNetwork-2:802-11-wireless
            Wired connection 1:ethernet
          OUT
          allow(subject).to receive(:run_os_command).with(%w[nmcli -t -f NAME,TYPE connection show])
            .and_return(command_result(stdout: nmcli_output))

          result = subject.preferred_networks
          expect(result).to be_an(Array)
          expect(result).to include('TestNetwork-1', 'TestNetwork-2')
          expect(result).not_to include('Wired connection 1')
        end

        it 'returns empty array when no Wi-Fi connections exist' do
          nmcli_output = "Wired connection 1:ethernet\nVPN profile:vpn"
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f NAME,TYPE connection show])
            .and_return(command_result(stdout: nmcli_output))

          expect(subject.preferred_networks).to eq([])
        end

        it 'filters out empty lines and non-Wi-Fi connections from output' do
          nmcli_output = "TestNetwork:802-11-wireless\n\n\nWired connection:ethernet\nVPN profile:vpn"
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f NAME,TYPE connection show])
            .and_return(command_result(stdout: nmcli_output))

          result = subject.preferred_networks
          expect(result).to eq(['TestNetwork'])
        end
      end

      describe '#nameservers' do
        it 'returns nameservers from resolv.conf' do
          allow(subject).to receive_messages(
            active_connection_profile_name: nil,
            _connected_network_name:        nil,
            nameservers_using_resolv_conf:  ['8.8.8.8', '8.8.4.4']
          )

          expect(subject.nameservers).to eq(['8.8.8.8', '8.8.4.4'])
        end

        it 'returns empty array when no nameservers configured' do
          allow(subject).to receive_messages(
            active_connection_profile_name: nil,
            _connected_network_name:        nil,
            nameservers_using_resolv_conf:  []
          )

          expect(subject.nameservers).to eq([])
        end
      end

      describe '#_ip_address' do
        it 'returns IP address from interface' do
          ip_output = <<~OUT.chomp
            2: wlp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
            inet 192.168.1.100/24 brd 192.168.1.255 scope global dynamic noprefixroute wlp3s0
          OUT
          wifi_interface = 'wlp3s0'

          allow(subject).to receive(:wifi_interface).and_return(wifi_interface)
          allow(subject).to receive(:run_os_command)
            .with(['ip', '-4', 'addr', 'show', wifi_interface], false)
            .and_return(command_result(stdout: ip_output))

          expect(subject.send(:_ip_address)).to eq('192.168.1.100')
        end

        it 'returns nil when no IP address assigned' do
          allow(subject).to receive(:wifi_interface).and_return('wlp3s0')
          allow(subject).to receive(:run_os_command)
            .with(['ip', '-4', 'addr', 'show', 'wlp3s0'], false)
            .and_return(command_result(stdout: ''))

          expect(subject.send(:_ip_address)).to be_nil
        end

        it 'handles multiple IP addresses by returning first' do
          ip_output = <<~OUT.chomp
            2: wlp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP>
            inet 192.168.1.100/24 brd 192.168.1.255 scope global
            inet 10.0.0.50/24 brd 10.0.0.255 scope global secondary
          OUT
          allow(subject).to receive(:wifi_interface).and_return('wlp3s0')
          allow(subject).to receive(:run_os_command)
            .with(['ip', '-4', 'addr', 'show', 'wlp3s0'], false)
            .and_return(command_result(stdout: ip_output))

          expect(subject.send(:_ip_address)).to eq('192.168.1.100')
        end
      end

      describe '#mac_address' do
        it 'returns MAC address of wifi interface' do
          mac_output = <<~OUT.chomp
            2: wlp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP mode DORMANT group default qlen 1000
            link/ether aa:bb:cc:dd:ee:ff brd ff:ff:ff:ff:ff:ff
          OUT
          wifi_interface = 'wlp3s0'

          allow(subject).to receive(:wifi_interface).and_return(wifi_interface)
          allow(subject).to receive(:run_os_command)
            .with(['ip', 'link', 'show', wifi_interface], false)
            .and_return(command_result(stdout: mac_output))

          expect(subject.mac_address).to eq('aa:bb:cc:dd:ee:ff')
        end

        it 'returns nil when no MAC address found' do
          allow(subject).to receive(:wifi_interface).and_return('wlp3s0')
          allow(subject).to receive(:run_os_command)
            .with(%w[ip link show wlp3s0], false)
            .and_return(command_result(stdout: ''))

          expect(subject.mac_address).to be_nil
        end
      end

      describe '#connection_security_type' do
        let(:network_name) { 'TestNetwork' }
        let(:nmcli_security_output) do
          "TestNetwork:WPA2\nOtherNetwork:WPA1 WPA2\nOpenNetwork:\nWEPNetwork:WEP"
        end

        before do
          allow(subject).to receive(:_connected_network_name).and_return(network_name)
        end

        [
          ['WPA2',                  'TestNetwork:WPA2',      'WPA2'],
          ['WPA3',                  'TestNetwork:WPA3',      'WPA3'],
          ['WPA',                   'TestNetwork:WPA',       'WPA'],
          ['WPA1',                  'TestNetwork:WPA1',      'WPA'],
          ['WEP',                   'TestNetwork:WEP',       'WEP'],
          ['Mixed WPA',             'TestNetwork:WPA1 WPA2', 'WPA2'],
          ['empty security (open)', 'TestNetwork:',          nil],
          ['unknown security',      'TestNetwork:UNKNOWN',   nil],
        ].each do |description, nmcli_line, expected|
          it "returns #{expected || 'nil'} for #{description}" do
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], false)
              .and_return(command_result(stdout: nmcli_line))

            expect(subject.connection_security_type).to eq(expected)
          end
        end

        it 'returns nil when not connected to any network' do
          allow(subject).to receive(:_connected_network_name).and_return(nil)

          expect(subject.connection_security_type).to be_nil
        end

        it 'returns nil when network not found in scan results' do
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], false)
            .and_return(command_result(stdout: 'OtherNetwork:WPA2'))

          expect(subject.connection_security_type).to be_nil
        end

        it 'returns nil when nmcli command fails' do
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], false)
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(1, 'nmcli', 'Command failed'))

          expect(subject.connection_security_type).to be_nil
        end
      end

      describe '#network_hidden?' do
        let(:network_name) { 'TestNetwork' }
        let(:profile_name) { 'TestNetwork' }

        before do
          allow(subject).to receive_messages(
            _connected_network_name:        network_name,
            active_connection_profile_name: profile_name
          )
        end

        it 'returns true when connection profile has hidden=yes' do
          hidden_output = "802-11-wireless.hidden:yes\n"
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', '-t', '-f', '802-11-wireless.hidden', 'connection', 'show', profile_name], false)
            .and_return(command_result(stdout: hidden_output))

          expect(subject.network_hidden?).to be true
        end

        it 'returns false when connection profile has hidden=no' do
          visible_output = "802-11-wireless.hidden:no\n"
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', '-t', '-f', '802-11-wireless.hidden', 'connection', 'show', profile_name], false)
            .and_return(command_result(stdout: visible_output))

          expect(subject.network_hidden?).to be false
        end

        it 'returns false when not connected to any network' do
          allow(subject).to receive(:_connected_network_name).and_return(nil)

          expect(subject.network_hidden?).to be false
        end

        it 'returns false when hidden line is not found in output' do
          other_output = "802-11-wireless.ssid:TestNetwork\n"
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', '-t', '-f', '802-11-wireless.hidden', 'connection', 'show', profile_name], false)
            .and_return(command_result(stdout: other_output))

          expect(subject.network_hidden?).to be false
        end

        it 'returns false when nmcli command fails' do
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', '-t', '-f', '802-11-wireless.hidden', 'connection', 'show', profile_name], false)
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(1, 'nmcli', 'Command failed'))

          expect(subject.network_hidden?).to be false
        end

        it 'uses network name when active connection profile is nil' do
          allow(subject).to receive(:active_connection_profile_name).and_return(nil)
          hidden_output = "802-11-wireless.hidden:yes\n"
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', '-t', '-f', '802-11-wireless.hidden', 'connection', 'show', network_name], false)
            .and_return(command_result(stdout: hidden_output))

          expect(subject.network_hidden?).to be true
        end
      end

      describe '#default_interface' do
        it 'returns interface from default route' do
          route_output = 'default via 192.168.1.1 dev wlp3s0 proto dhcp metric 600'
          allow(subject).to receive(:run_os_command)
            .with(%w[ip route show default], false)
            .and_return(command_result(stdout: route_output))

          expect(subject.default_interface).to eq('wlp3s0')
        end

        it 'returns nil when no default route exists' do
          allow(subject).to receive(:run_os_command)
            .with(%w[ip route show default], false)
            .and_return(command_result(stdout: ''))

          expect(subject.default_interface).to be_nil
        end
      end

      # Happy path testing for core functionality
      describe '#wifi_on?' do
        it 'correctly detects wifi enabled state' do
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli radio wifi], false)
            .and_return(command_result(stdout: 'enabled'))

          expect(subject.wifi_on?).to be(true)
        end

        it 'correctly detects wifi disabled state' do
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli radio wifi], false)
            .and_return(command_result(stdout: 'disabled'))

          expect(subject.wifi_on?).to be(false)
        end
      end

      describe '#available_network_names' do
        it 'returns sorted list of available networks by signal strength' do
          nmcli_output = "TestNet1:75\nStrongNet:90\nWeakNet:25\nTestNet2:80"
          # Mock wifi_on? check that happens in BaseModel#available_network_names
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli radio wifi], false)
            .and_return(command_result(stdout: 'enabled'))
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f SSID,SIGNAL dev wifi list])
            .and_return(command_result(stdout: nmcli_output))

          result = subject.available_network_names
          expect(result).to eq(%w[StrongNet TestNet2 TestNet1 WeakNet])
        end

        it 'does not filter out the connected SSID when the Ubuntu scan includes it' do
          nmcli_output = "CurrentNet:95\nOtherNet:80\nWeakNet:25"
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli radio wifi], false)
            .and_return(command_result(stdout: 'enabled'))
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f SSID,SIGNAL dev wifi list])
            .and_return(command_result(stdout: nmcli_output))
          allow(subject).to receive(:_connected_network_name).and_return('CurrentNet')

          expect(subject.available_network_names).to eq(%w[CurrentNet OtherNet WeakNet])
        end

        it 'does not inject the connected SSID when the Ubuntu scan omits it' do
          nmcli_output = "OtherNet:90\nWeakNet:25"
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli radio wifi], false)
            .and_return(command_result(stdout: 'enabled'))
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f SSID,SIGNAL dev wifi list])
            .and_return(command_result(stdout: nmcli_output))
          allow(subject).to receive(:_connected_network_name).and_return('CurrentNet')

          expect(subject.available_network_names).to eq(%w[OtherNet WeakNet])
        end

        it 'removes duplicate network names' do
          nmcli_output = "TestNet:75\nTestNet:80\nOtherNet:90"
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli radio wifi], false)
            .and_return(command_result(stdout: 'enabled'))
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f SSID,SIGNAL dev wifi list])
            .and_return(command_result(stdout: nmcli_output))

          result = subject.available_network_names
          expect(result).to eq(%w[OtherNet TestNet])
        end

        it 'filters out empty SSIDs' do
          # NOTE: empty SSIDs show up as lines starting with ':' (colon)
          nmcli_output = "TestNet:75\n:80\nOtherNet:90\n:60"
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli radio wifi], false)
            .and_return(command_result(stdout: 'enabled'))
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f SSID,SIGNAL dev wifi list])
            .and_return(command_result(stdout: nmcli_output))

          result = subject.available_network_names
          expect(result).to eq(%w[OtherNet TestNet])
        end
      end

      describe '#is_wifi_interface?' do
        it 'returns true for valid wifi interface' do
          allow(subject).to receive(:run_os_command)
            .with(/iw dev wlp3s0 info 2>\/dev\/null/, false)
            .and_return(command_result(stdout: 'Interface wlp3s0\n\ttype managed'))

          expect(subject.is_wifi_interface?('wlp3s0')).to be(true)
        end

        it 'returns false for non-wifi interface' do
          allow(subject).to receive(:run_os_command)
            .with(/iw dev eth0 info 2>\/dev\/null/, false)
            .and_return(command_result(stdout: ''))

          expect(subject.is_wifi_interface?('eth0')).to be(false)
        end
      end

      describe '#set_nameservers' do
        it 'successfully sets custom nameservers' do
          nameservers = ['8.8.8.8', '1.1.1.1']
          connection_name = 'MyHomeNetwork'

          allow(subject).to receive(:active_connection_profile_name).and_return(connection_name)
          allow(subject).to receive(:nameservers_from_connection).with(connection_name)
            .and_return(nameservers)

          # Mock the connection-based DNS commands
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', nameservers.join(' ')])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'yes'])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .and_return(command_result(stdout: ''))

          result = subject.set_nameservers(nameservers)
          expect(result).to eq(nameservers)
        end

        it 'successfully clears nameservers' do
          connection_name = 'MyHomeNetwork'

          allow(subject).to receive(:active_connection_profile_name).and_return(connection_name)
          allow(subject).to receive(:nameservers_from_connection).with(connection_name).and_return([])
          # Expect both IPv4 and IPv6 clear commands
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', ''])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'no'])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns', ''])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'no'])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .and_return(command_result(stdout: ''))

          result = subject.set_nameservers(:clear)
          expect(result).to eq(:clear)
        end

        it 'uses the active profile when it differs from the SSID' do
          profile_name = 'Office Profile'
          ssid_name = 'OfficeWiFi'
          nameservers = ['4.4.4.4']

          allow(subject).to receive_messages(
            active_connection_profile_name: profile_name,
            _connected_network_name:        ssid_name
          )
          allow(subject).to receive(:nameservers_from_connection).with(profile_name).and_return(nameservers)

          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', profile_name, 'ipv4.dns', nameservers.join(' ')])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', profile_name, 'ipv4.ignore-auto-dns', 'yes'])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'up', profile_name])
            .and_return(command_result(stdout: ''))

          result = subject.set_nameservers(nameservers)
          expect(result).to eq(nameservers)
        end

        it 'accepts and configures IPv6 DNS addresses' do
          ipv6_nameservers = ['2606:4700:4700::1111', '2606:4700:4700::1001']
          connection_name = 'MyHomeNetwork'

          allow(subject).to receive(:active_connection_profile_name).and_return(connection_name)
          allow(subject).to receive(:nameservers_from_connection).with(connection_name)
            .and_return(ipv6_nameservers)

          # Expect IPv6 DNS commands
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns',
              ipv6_nameservers.join(' ')])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'yes'])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .and_return(command_result(stdout: ''))

          result = subject.set_nameservers(ipv6_nameservers)
          expect(result).to eq(ipv6_nameservers)
        end

        it 'accepts mixed IPv4 and IPv6 DNS addresses' do
          mixed_nameservers = ['8.8.8.8', '2606:4700:4700::1111', '1.1.1.1']
          connection_name = 'MyHomeNetwork'

          allow(subject).to receive(:active_connection_profile_name).and_return(connection_name)
          allow(subject).to receive(:nameservers_from_connection).with(connection_name)
            .and_return(mixed_nameservers)

          # Expect both IPv4 and IPv6 DNS commands
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', '8.8.8.8 1.1.1.1'])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'yes'])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns',
              '2606:4700:4700::1111'])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'yes'])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .and_return(command_result(stdout: ''))

          result = subject.set_nameservers(mixed_nameservers)
          expect(result).to eq(mixed_nameservers)
        end

        it 'replaces a previously dual-stack profile with IPv4-only DNS' do
          connection_name = 'MyHomeNetwork'
          nameservers = ['8.8.8.8', '1.1.1.1']

          allow(subject).to receive(:active_connection_profile_name).and_return(connection_name)

          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', '8.8.8.8 1.1.1.1'])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'yes'])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns', ''])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'no'])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .ordered.and_return(command_result(stdout: ''))

          result = subject.set_nameservers(nameservers)
          expect(result).to eq(nameservers)
        end

        it 'replaces a previously dual-stack profile with IPv6-only DNS' do
          connection_name = 'MyHomeNetwork'
          nameservers = ['2606:4700:4700::1111', '2606:4700:4700::1001']

          allow(subject).to receive(:active_connection_profile_name).and_return(connection_name)

          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', ''])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'no'])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns',
              '2606:4700:4700::1111 2606:4700:4700::1001'])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'yes'])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .ordered.and_return(command_result(stdout: ''))

          result = subject.set_nameservers(nameservers)
          expect(result).to eq(nameservers)
        end

        it 'replaces a previously single-stack profile with the opposite address family' do
          connection_name = 'MyHomeNetwork'
          nameservers = ['2606:4700:4700::1111']

          allow(subject).to receive(:active_connection_profile_name).and_return(connection_name)

          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', ''])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'no'])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns',
              '2606:4700:4700::1111'])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'yes'])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .ordered.and_return(command_result(stdout: ''))

          result = subject.set_nameservers(nameservers)
          expect(result).to eq(nameservers)
        end

        it 'clears both IPv4 and IPv6 nameservers when :clear is specified' do
          connection_name = 'MyHomeNetwork'

          allow(subject).to receive(:active_connection_profile_name).and_return(connection_name)
          allow(subject).to receive(:nameservers_from_connection).with(connection_name).and_return([])

          # Expect both IPv4 and IPv6 clear commands
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', ''])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'no'])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns', ''])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'no'])
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .and_return(command_result(stdout: ''))

          result = subject.set_nameservers(:clear)
          expect(result).to eq(:clear)
        end
      end

      describe '#_connected_network_name' do
        it 'returns name of currently connected network' do
          nmcli_output = "yes:MyHomeNetwork\nno:OtherNetwork"
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f active,ssid device wifi], false)
            .and_return(command_result(stdout: nmcli_output))

          expect(subject.send(:_connected_network_name)).to eq('MyHomeNetwork')
        end

        it 'returns nil when not connected to any network' do
          nmcli_output = "no:Network1\nno:Network2"
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f active,ssid device wifi], false)
            .and_return(command_result(stdout: nmcli_output))

          expect(subject.send(:_connected_network_name)).to be_nil
        end
      end

      describe '#active_connection_profile_name' do
        it 'parses the active profile from nmcli dev show output' do
          allow(subject).to receive(:wifi_interface).and_return('wlp3s0')
          nmcli_output = "GENERAL.CONNECTION:Office Profile\nGENERAL.DEVICE:wlp3s0"
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', '-t', '-f', 'GENERAL.CONNECTION', 'dev', 'show', 'wlp3s0'], false)
            .and_return(command_result(stdout: nmcli_output))

          expect(subject.active_connection_profile_name).to eq('Office Profile')
        end

        it 'returns nil when wifi interface cannot be determined' do
          allow(subject).to receive(:wifi_interface).and_return(nil)
          expect(subject.active_connection_profile_name).to be_nil
        end

        it 'returns nil when nmcli lookup fails' do
          allow(subject).to receive(:wifi_interface).and_return('wlp3s0')
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', '-t', '-f', 'GENERAL.CONNECTION', 'dev', 'show', 'wlp3s0'], false)
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(10, 'nmcli', 'failed'))

          expect(subject.active_connection_profile_name).to be_nil
        end
      end

      describe '#connection_ready?' do
        it 'returns true for an active matching connection even without an IPv4 address' do
          allow(subject).to receive_messages(
            _connected_network_name:        'NetA',
            active_connection_profile_name: 'NetA',
            connected?:                     true,
            _ip_address:                    nil
          )

          expect(subject.connection_ready?('NetA')).to be(true)
        end

        it 'returns false when the active profile is missing' do
          allow(subject).to receive_messages(
            _connected_network_name:        'NetA',
            active_connection_profile_name: nil,
            connected?:                     true
          )

          expect(subject.connection_ready?('NetA')).to be(false)
        end
      end

      describe 'private helper methods' do
        describe '#get_security_parameter' do
          it 'detects WPA2 security and returns correct parameter' do
            wifi_list_output = 'MyNetwork:WPA2'
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], false)
              .and_return(command_result(stdout: wifi_list_output))

            result = subject.send(:get_security_parameter, 'MyNetwork')
            expect(result).to eq('802-11-wireless-security.psk')
          end

          it 'detects WEP security and returns correct parameter' do
            wifi_list_output = 'MyNetwork:WEP'
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], false)
              .and_return(command_result(stdout: wifi_list_output))

            result = subject.send(:get_security_parameter, 'MyNetwork')
            expect(result).to eq('802-11-wireless-security.wep-key0')
          end

          it 'returns nil when network not found in scan' do
            wifi_list_output = 'OtherNetwork:WPA2'
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], false)
              .and_return(command_result(stdout: wifi_list_output))

            expect(subject.send(:get_security_parameter, 'NonExistent')).to be_nil
          end
        end

        describe '#find_best_profile_for_ssid' do
          it 'finds existing connection profile for SSID' do
            # NetworkManager names duplicates "SSID", "SSID 1", "SSID 2", etc.
            connection_output = "MyNetwork:1672574400\nMyNetwork 1:1672660200\nOtherNetwork:1672547800"
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli -t -f NAME,TIMESTAMP connection show], false)
              .and_return(command_result(stdout: connection_output))

            result = subject.send(:find_best_profile_for_ssid, 'MyNetwork')
            expect(result).to eq('MyNetwork 1')  # Most recent profile
          end

          it 'returns nil when no profile exists for SSID' do
            connection_output = "MyNetwork:1672574400\nOtherNetwork:1672547800"
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli -t -f NAME,TIMESTAMP connection show], false)
              .and_return(command_result(stdout: connection_output))

            expect(subject.send(:find_best_profile_for_ssid, 'NonExistent')).to be_nil
          end
        end

        describe '#_preferred_network_password' do
          it 'retrieves stored PSK password for connection profile' do
            password_output = '802-11-wireless-security.psk:    my-secret-password'
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli --show-secrets connection show MyProfile], false)
              .and_return(command_result(stdout: password_output))

            result = subject.send(:_preferred_network_password, 'MyProfile')
            expect(result).to eq('my-secret-password')
          end

          it 'retrieves stored WEP password for connection profile' do
            password_output = '802-11-wireless-security.wep-key0:    legacy-wep-key'
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli --show-secrets connection show MyProfile], false)
              .and_return(command_result(stdout: password_output))

            result = subject.send(:_preferred_network_password, 'MyProfile')
            expect(result).to eq('legacy-wep-key')
          end

          it 'returns nil when no password is stored' do
            password_output = <<~OUTPUT
              connection.id: MyProfile
              802-11-wireless-security.key-mgmt: none
            OUTPUT
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli --show-secrets connection show MyProfile], false)
              .and_return(command_result(stdout: password_output))

            expect(subject.send(:_preferred_network_password, 'MyProfile')).to be_nil
          end
        end
      end

      # Regression tests: nmcli terse output with colons in SSIDs/profiles
      describe 'nmcli colon-safe parsing' do
        describe '#_available_network_names with colon-containing SSIDs' do
          it 'correctly parses an SSID that contains a literal colon' do
            # nmcli escapes the colon in "Cafe:Guest" as "Cafe\:Guest"
            nmcli_output = "Cafe\\:Guest:75\nRegularNet:90"
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli radio wifi], false)
              .and_return(command_result(stdout: 'enabled'))
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli -t -f SSID,SIGNAL dev wifi list])
              .and_return(command_result(stdout: nmcli_output))

            result = subject.available_network_names
            expect(result).to include('Cafe:Guest', 'RegularNet')
          end
        end

        describe '#_connected_network_name with colon-containing SSID' do
          it 'returns the full SSID including its embedded colon' do
            nmcli_output = "no:RegularNet\nyes:Corp\\:Wifi"
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli -t -f active,ssid device wifi], false)
              .and_return(command_result(stdout: nmcli_output))

            expect(subject.send(:_connected_network_name)).to eq('Corp:Wifi')
          end
        end

        describe '#get_security_parameter with colon-containing SSID' do
          it 'matches the exact SSID and returns the correct security parameter' do
            # "Corp:Wifi" is escaped as "Corp\:Wifi" in nmcli terse output
            nmcli_output = "Corp\\:Wifi:WPA2\nCorpNet:WPA2"
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], false)
              .and_return(command_result(stdout: nmcli_output))

            expect(subject.send(:get_security_parameter, 'Corp:Wifi')).to eq('802-11-wireless-security.psk')
          end

          it 'does not match a prefix-collision SSID (Office vs Office-Guest)' do
            nmcli_output = "Office-Guest:WPA2\nOtherNet:WPA2"
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], false)
              .and_return(command_result(stdout: nmcli_output))

            expect(subject.send(:get_security_parameter, 'Office')).to be_nil
          end
        end

        describe '#find_best_profile_for_ssid with colon-containing profile name' do
          it 'correctly parses profile names that contain literal colons' do
            # nmcli escapes "Corp:Net" as "Corp\:Net" in terse output
            connection_output = "Corp\\:Net:1672660200\nOtherNetwork:1672574400"
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli -t -f NAME,TIMESTAMP connection show], false)
              .and_return(command_result(stdout: connection_output))

            expect(subject.send(:find_best_profile_for_ssid, 'Corp:Net')).to eq('Corp:Net')
          end

          it 'does not match a profile whose name merely starts with the SSID (prefix collision)' do
            connection_output = "Office-Guest:1672660200\nOffice Extra:1672574400"
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli -t -f NAME,TIMESTAMP connection show], false)
              .and_return(command_result(stdout: connection_output))

            expect(subject.send(:find_best_profile_for_ssid, 'Office')).to be_nil
          end

          it 'matches an NM duplicate profile (SSID followed by space and number)' do
            connection_output = "Office:1672574400\nOffice 1:1672660200\nOffice-Guest:1672547800"
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli -t -f NAME,TIMESTAMP connection show], false)
              .and_return(command_result(stdout: connection_output))

            result = subject.send(:find_best_profile_for_ssid, 'Office')
            expect(result).to eq('Office 1')
          end
        end

        describe '#connection_security_type with colon-containing SSID' do
          it 'returns the correct security type for an SSID with a colon' do
            allow(subject).to receive(:_connected_network_name).and_return('Corp:Wifi')
            nmcli_output = "Corp\\:Wifi:WPA2\nCorpNet:WPA2"
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], false)
              .and_return(command_result(stdout: nmcli_output))

            expect(subject.connection_security_type).to eq('WPA2')
          end

          it 'does not misidentify a prefix-collision SSID (Office vs Office-Guest)' do
            allow(subject).to receive(:_connected_network_name).and_return('Office')
            nmcli_output = 'Office-Guest:WPA2'
            allow(subject).to receive(:run_os_command)
              .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], false)
              .and_return(command_result(stdout: nmcli_output))

            expect(subject.connection_security_type).to be_nil
          end
        end
      end
    end

    context 'when running error handling tests' do
      describe '#wifi_on' do
        it 'raises WifiEnableError when command succeeds but wifi remains off' do
          # Mock specific command calls to avoid real system calls
          allow(subject).to receive(:run_os_command).with(/nmcli radio wifi on/, anything)
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command).with(/nmcli radio wifi$/, anything)
            .and_return(command_result(stdout: 'disabled'))

          # Mock the till method to immediately raise WaitTimeoutError (which wifi_on catches and converts to WifiEnableError)
          allow(subject).to receive(:till).and_raise(WifiWand::WaitTimeoutError.new(:wifi_on, 5))

          expect { subject.wifi_on }.to raise_error(WifiWand::WifiEnableError)
        end
      end

      describe '#wifi_off' do
        it 'raises WifiDisableError when command succeeds but wifi remains on' do
          # Mock specific command calls to avoid real system calls
          allow(subject).to receive(:run_os_command).with(%w[nmcli radio wifi off], anything)
            .and_return(command_result(stdout: ''))
          allow(subject).to receive(:run_os_command).with(%w[nmcli radio wifi], anything)
            .and_return(command_result(stdout: 'enabled'))

          # Mock the till method to immediately raise WaitTimeoutError (which wifi_off catches and converts to WifiDisableError)
          allow(subject).to receive(:till).and_raise(WifiWand::WaitTimeoutError.new(:wifi_off, 5))

          expect { subject.wifi_off }.to raise_error(WifiWand::WifiDisableError)
        end
      end

      describe '#disconnect' do
        it 'handles nmcli disconnect failures gracefully' do
          allow(subject).to receive_messages(wifi_on?: true, associated?: true, wifi_interface: 'wlan0')
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli dev disconnect wlan0])
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(1, 'nmcli dev disconnect wlan0',
              'Device disconnect failed'))

          expect { subject.disconnect }
            .to raise_error(WifiWand::CommandExecutor::OsCommandError, /Device disconnect failed/)
        end

        it 'is a no-op when already disconnected' do
          allow(subject).to receive_messages(wifi_on?: true, associated?: false)
          allow(subject).to receive(:run_os_command)
          allow(subject).to receive(:till)

          expect(subject.disconnect).to be_nil
          expect(subject).not_to have_received(:run_os_command)
          expect(subject).not_to have_received(:till)
        end
      end

      describe '#set_nameservers' do
        it 'raises error for invalid IP addresses' do
          invalid_nameservers = ['invalid.ip', '256.256.256.256']
          connection_name = 'MyHomeNetwork'

          allow(subject).to receive(:active_connection_profile_name).and_return(connection_name)

          # Capture stdout to suppress the "invalid address:" output from IP validation
          original_stdout = $stdout
          $stdout = StringIO.new
          begin
            expect { subject.set_nameservers(invalid_nameservers) }.to raise_error(WifiWand::InvalidIPAddressError)
          ensure
            $stdout = original_stdout
          end
        end

        it 'raises a DNS configuration error when custom DNS modification fails' do
          connection_name = 'MyHomeNetwork'

          allow(subject).to receive(:active_connection_profile_name).and_return(connection_name)
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', '8.8.8.8'])
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(
              1,
              'nmcli connection modify',
              'Connection modify failed'
            ))

          expect { subject.set_nameservers(['8.8.8.8']) }
            .to raise_error(WifiWand::DnsConfigurationError, /modifying the connection profile/)
        end

        it 'raises a DNS configuration error when clearing DNS fails' do
          connection_name = 'MyHomeNetwork'

          allow(subject).to receive(:active_connection_profile_name).and_return(connection_name)
          allow(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', ''])
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(
              1,
              'nmcli connection modify',
              'Permission denied'
            ))

          expect { subject.set_nameservers(:clear) }
            .to raise_error(WifiWand::DnsConfigurationError, /Permission denied/)
        end

        it 'raises a DNS configuration error when connection activation fails after modification' do
          connection_name = 'MyHomeNetwork'
          nameservers = ['8.8.8.8']

          allow(subject).to receive(:active_connection_profile_name).and_return(connection_name)
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', '8.8.8.8'])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'yes'])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns', ''])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'no'])
            .ordered.and_return(command_result(stdout: ''))
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .ordered.and_raise(WifiWand::CommandExecutor::OsCommandError.new(
              1,
              'nmcli connection up',
              'Activation failed'
            ))

          expect { subject.set_nameservers(nameservers) }
            .to raise_error(WifiWand::DnsConfigurationError, /reactivating the connection/)
        end

        it 'handles cases when no active connection exists' do
          # Mock no active connection
          allow(subject).to receive_messages(
            active_connection_profile_name: nil,
            _connected_network_name:        nil
          )

          expect { subject.set_nameservers(['8.8.8.8']) }
            .to raise_error(WifiWand::WifiInterfaceError, /No active Wi-Fi connection/)
        end
      end

      describe '#available_network_names' do
        it 'handles nmcli scan failures' do
          # Mock wifi_on? to return true so available_network_names calls _available_network_names
          allow(subject).to receive(:wifi_on?).and_return(true)
          # Mock the specific command to fail
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli -t -f SSID,SIGNAL dev wifi list])
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(1,
              'nmcli -t -f SSID,SIGNAL dev wifi list', 'Scan failed'))

          expect { subject.available_network_names }
            .to raise_error(WifiWand::CommandExecutor::OsCommandError, /Scan failed/)
        end
      end

      describe '#is_wifi_interface?' do
        it 'handles iw dev info command failures' do
          # Mock iw dev info to fail without real commands
          allow(subject).to receive(:run_os_command)
            .with(/iw dev .* info 2>\/dev\/null/, false)
            # When command fails with raise_on_error=false, it returns empty string
            .and_return(command_result(stdout: ''))

          expect(subject.is_wifi_interface?('wlan0')).to be(false)
        end
      end

      describe '#_connect error scenarios' do
        it 'raises NetworkNotFoundError for non-existent network' do
          # Mock nmcli to simulate network not found scenario without real commands
          allow(subject).to receive_messages(_connected_network_name: nil, find_best_profile_for_ssid: nil)
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli dev wifi connect non_existent_network_123])
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(10, 'nmcli dev wifi connect',
              'No network with SSID "non_existent_network_123" found'))

          expect { subject._connect('non_existent_network_123') }.to raise_error(WifiWand::NetworkNotFoundError)
        end

        it 'raises NetworkConnectionError for generic connection activation failures' do
          # Mock various paths that _connect might take without real commands
          # Mock connection check
          # Mock profile finding
          allow(subject).to receive_messages(_connected_network_name: nil, find_best_profile_for_ssid: nil)
          # Mock the actual connection attempt that will be made
          allow(subject).to receive(:run_os_command)
            .with(%w[nmcli dev wifi connect TestNetwork password test_password])
            .and_raise(WifiWand::CommandExecutor::OsCommandError.new(4, 'nmcli dev wifi connect',
              'Connection activation failed'))

          # Generic activation failed should now raise NetworkConnectionError (out of range)
          expect { subject._connect('TestNetwork', 'test_password') }
            .to raise_error(WifiWand::NetworkConnectionError, /out of range/)
        end

        it 'handles security parameter detection failures gracefully' do
          # Mock get_security_parameter to return nil (detection failure)
          # Mock the fallback connection attempt to avoid real network connection
          allow(subject).to receive_messages(
            get_security_parameter:     command_result(stdout: nil),
            _connected_network_name:    nil,
            find_best_profile_for_ssid: nil
          )
          allow(subject).to receive(:run_os_command)
            .with(/nmcli dev wifi connect.*password/)
            .and_return(command_result(stdout: ''))  # Simulate successful connection

          # Should fall back to direct connection attempt without actually connecting
          expect { subject._connect('TestNetwork', 'test_password') }
            .not_to raise_error
        end
      end
    end

    # System-modifying tests (will change wifi state)
    context 'when running system-modifying operations',
      :real_env_read_write, real_env_os: :os_ubuntu do
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
        it 'disconnects from current network' do
          # Can disconnect even when not connected to a network
          expect { subject.disconnect }.not_to raise_error
        end
      end

      describe '#remove_preferred_network' do
        it 'removes a preferred network' do
          connection_name = 'SavedProfile'

          allow(subject).to receive(:preferred_networks).and_return([connection_name])
          expect(subject).to receive(:run_os_command)
            .with(['nmcli', 'connection', 'delete', connection_name])
            .and_return(command_result(stdout: ''))

          expect { subject.remove_preferred_network(connection_name) }.not_to raise_error
        end

        it 'handles removal of non-existent network' do
          allow(subject).to receive(:preferred_networks).and_return([])

          expect { subject.remove_preferred_network('non_existent_network_123') }.not_to raise_error
        end
      end

      describe '#set_nameservers' do
        let(:valid_nameservers) { ['8.8.8.8', '8.8.4.4'] }

        it 'sets valid nameservers' do
          subject.wifi_on

          result = subject.set_nameservers(valid_nameservers)
          expect(result).to eq(valid_nameservers)

          # Poll until the new nameservers appear in the active connection profile
          wait_for(timeout: 30, interval: 0.5, description: 'nameservers to be applied') do
            (valid_nameservers - subject.nameservers).empty?
          end

          expect(subject.nameservers).to include(*valid_nameservers)
        end
      end
    end

    context 'when running read-only real-environment checks',
      :real_env_read_only, real_env_os: :os_ubuntu do
      describe 'interface detection' do
        it 'detects WiFi interface correctly' do
          interface = subject.probe_wifi_interface
          expect(interface).to match(WIFI_INTERFACE_REGEX) if interface
        end

        it 'validates detected interface is actually WiFi' do
          interface = subject.wifi_interface
          expect(subject.is_wifi_interface?(interface)).to be(true) if interface
        end
      end

      describe 'network information' do
        it 'retrieves IP address' do
          expect(subject.ip_address).to match(/^\d+\.\d+\.\d+\.\d+$/)
        end

        it 'retrieves MAC address' do
          expect(subject.mac_address).to match(/^([0-9a-f]{2}:){5}[0-9a-f]{2}$/i)
        end

        it 'retrieves nameservers' do
          expect(subject.nameservers).to be_an(Array)
        end

        it 'returns a string or nil for connected network name' do
          skip 'WiFi is currently off' unless subject.wifi_on?
          expect(subject.connected_network_name).to be_nil_or_a_string
        end
      end

      describe 'network scanning' do
        it 'can scan for available networks when WiFi is already on' do
          skip 'WiFi is currently off' unless subject.wifi_on?

          networks = subject.available_network_names
          expect(networks).to be_an(Array)
        end
      end
    end
  end
end
