# frozen_string_literal: true

require 'timeout'

require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/platforms/ubuntu/model'

module WifiWand
  describe Platforms::Ubuntu::Model do
    subject(:ubuntu_model) { create_ubuntu_test_model }

    # Mock network connectivity tester to prevent real network calls during mocked tests
    before do
      unless uses_real_env?
        tester = WifiWand::NetworkConnectivityTester
        # rubocop:disable RSpec/AnyInstance -- file-level bootstrap stubs keep mocked model setup hermetic
        allow_any_instance_of(tester).to receive(:internet_connectivity_state).and_return(:reachable)
        allow_any_instance_of(tester).to receive(:tcp_connectivity?).and_return(true)
        allow_any_instance_of(tester).to receive(:dns_working?).and_return(true)
        # rubocop:enable RSpec/AnyInstance

        # Mock OS command execution to prevent real WiFi control commands
        allow(ubuntu_model).to receive_messages(run_command: command_result(stdout: ''), till: nil)
      end
    end

    def saved_wifi_profile(name, ssid: name, type: '802-11-wireless', timestamp: 0)
      WifiWand::Platforms::Ubuntu::Model::SavedWifiProfile.new(
        name:      name,
        ssid:      ssid,
        type:      type,
        timestamp: timestamp
      )
    end

    def nmcli_saved_profile_summary_fields
      %w[nmcli -t -f NAME,TYPE,TIMESTAMP connection show]
    end

    def nmcli_saved_profile_ssid_fields(profile_name)
      ['nmcli', '-t', '-f', '802-11-wireless.ssid', 'connection', 'show', profile_name]
    end

    def stub_saved_profile_ssid(profile_name, ssid)
      allow(ubuntu_model).to receive(:run_command)
        .with(nmcli_saved_profile_ssid_fields(profile_name), raise_on_error: false)
        .and_return(command_result(stdout: "802-11-wireless.ssid:#{ssid}"))
    end

    def wifi_interface_regex = /wl[a-z0-9]+/

    def nmcli_radio_cmd = 'nmcli radio wifi'

    # Mocked tests with proper stubbing
    context 'when running core functionality tests' do
      describe '#status_line_data' do
        let(:progress_callback) { ->(_data) {} }

        it 'uses the longer connectivity worker timeout for Ubuntu status checks' do
          expect(WifiWand::StatusLineDataBuilder).to receive(:call).with(
            ubuntu_model,
            progress_callback:                          progress_callback,
            runtime_config:                             ubuntu_model.runtime_config,
            expected_network_errors:                    WifiWand::NetworkErrorConstants::EXPECTED_NETWORK_ERRORS,
            connectivity_worker_result_timeout_seconds: WifiWand::TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT
          ).and_return({})

          ubuntu_model.status_line_data(progress_callback: progress_callback)
        end
      end

      describe '#wifi_on and #wifi_off failure paths' do
        it 'raises WifiEnableError when WiFi remains disabled after enable attempt' do
          allow(ubuntu_model).to receive(:wifi_on?).and_return(false, false)
          allow(ubuntu_model).to receive(:run_command).with(%w[nmcli radio wifi on])
            .and_return(command_result(stdout: ''))
          timeout = WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT
          allow(ubuntu_model).to receive(:till).with(:wifi_on, timeout_in_secs: timeout).and_return(nil)

          expect { ubuntu_model.wifi_on }.to raise_error(WifiWand::WifiEnableError)
        end

        it 'raises WifiDisableError when WiFi remains enabled after disable attempt' do
          allow(ubuntu_model).to receive(:wifi_on?).and_return(true, true)
          allow(ubuntu_model).to receive(:run_command).with(%w[nmcli radio wifi off])
            .and_return(command_result(stdout: ''))
          timeout = WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT
          allow(ubuntu_model).to receive(:till).with(:wifi_off, timeout_in_secs: timeout).and_return(nil)

          expect { ubuntu_model.wifi_off }.to raise_error(WifiWand::WifiDisableError)
        end
      end

      describe '#_connect early return and branches' do
        # Helper method to set up common _connect test mocking
        def setup_connect_test(connected_network: nil, profile_name: nil, old_password: nil,
          security_param: nil)
          allow(ubuntu_model).to receive(:_connected_network_name).and_return(connected_network)
          if profile_name
            allow(ubuntu_model).to receive(:find_best_profile_for_ssid).and_return(profile_name)
            if old_password
              allow(ubuntu_model).to receive(:_preferred_network_password).and_return(old_password)
            end
            if security_param
              allow(ubuntu_model).to receive(:get_security_parameter).and_return(security_param)
            end
          else
            allow(ubuntu_model).to receive(:find_best_profile_for_ssid).and_return(nil)
          end
        end

        it 'returns immediately when already connected to target network' do
          allow(ubuntu_model).to receive(:connected?).and_return(true)
          setup_connect_test(connected_network: 'NetA')
          expect(ubuntu_model).not_to receive(:run_command)
          expect { ubuntu_model._connect('NetA') }.not_to raise_error
        end

        it 'does not return early when SSID matches but NetworkManager is not fully connected' do
          allow(ubuntu_model).to receive(:connected?).and_return(false)
          setup_connect_test(connected_network: 'NetA', profile_name: 'NetA')

          expect(ubuntu_model).to receive(:run_command).with(%w[nmcli connection up NetA])
            .and_return(command_result(stdout: ''))
          expect { ubuntu_model._connect('NetA') }.not_to raise_error
        end

        it 'updates an existing profile before activating it with a changed password' do
          setup_connect_test(profile_name: 'SSID1', old_password: 'oldpass',
            security_param: '802-11-wireless-security.psk')

          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli connection modify SSID1 802-11-wireless-security.psk newpass])
            .ordered
            .and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli connection up SSID1])
            .ordered
            .and_return(command_result(stdout: ''))
          expect(ubuntu_model).not_to receive(:run_command)
            .with(%w[nmcli dev wifi connect SSID1 password newpass])
          expect { ubuntu_model._connect('SSID1', 'newpass') }.not_to raise_error
        end

        it 'rolls back an updated profile password when activation fails' do
          setup_connect_test(profile_name: 'SSID1', old_password: 'oldpass',
            security_param: '802-11-wireless-security.psk')

          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli connection modify SSID1 802-11-wireless-security.psk wrongpass])
            .ordered
            .and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli connection up SSID1])
            .ordered
            .and_raise(
              os_command_error(
                exitstatus: 4,
                command:    'nmcli connection up',
                text:       'Error: Connection activation failed: (53) authentication failed'
              )
            )
          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli connection modify SSID1 802-11-wireless-security.psk oldpass])
            .ordered
            .and_return(command_result(stdout: ''))
          expect(ubuntu_model).not_to receive(:run_command)
            .with(%w[nmcli dev wifi connect SSID1 password wrongpass])
          expect { ubuntu_model._connect('SSID1', 'wrongpass') }
            .to raise_error(WifiWand::NetworkAuthenticationError, /SSID1/)
        end

        context 'with non-verbose error output' do
          subject(:ubuntu_model) do
            create_ubuntu_test_model(verbose: false, err_stream: err_stream)
          end

          let(:err_stream) { StringIO.new }

          it 'warns when rollback of an updated profile password fails' do
            setup_connect_test(profile_name: 'SSID1', old_password: 'oldpass',
              security_param: '802-11-wireless-security.psk')

            expect(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli connection modify SSID1 802-11-wireless-security.psk wrongpass])
              .ordered
              .and_return(command_result(stdout: ''))
            expect(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli connection up SSID1])
              .ordered
              .and_raise(
                os_command_error(
                  exitstatus: 4,
                  command:    'nmcli connection up',
                  text:       'Error: Connection activation failed: (53) authentication failed'
                )
              )
            expect(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli connection modify SSID1 802-11-wireless-security.psk oldpass])
              .ordered
              .and_raise(
                os_command_error(
                  exitstatus: 4,
                  command:    'nmcli connection modify',
                  text:       'rollback modify failed'
                )
              )

            expect { ubuntu_model._connect('SSID1', 'wrongpass') }
              .to raise_error(WifiWand::NetworkAuthenticationError, /SSID1/)
            expect(err_stream.string).to include(
              "Warning: password rollback failed for 'SSID1':"
            )
            expect(err_stream.string).to include(
              'You may need to re-enter the password for this network.'
            )
          end
        end

        it 'targets the best matching profile for password updates' do
          setup_connect_test(profile_name: 'SSID1', old_password: 'oldpass',
            security_param: '802-11-wireless-security.psk')
          allow(ubuntu_model).to receive(:find_best_profile_for_ssid).and_return('SSID1 2')
          allow(ubuntu_model).to receive(:_preferred_network_password).with('SSID1 2').and_return('oldpass')

          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', 'SSID1 2', '802-11-wireless-security.psk', 'newpass'])
            .ordered
            .and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'up', 'SSID1 2'])
            .ordered
            .and_return(command_result(stdout: ''))
          expect(ubuntu_model).not_to receive(:run_command)
            .with(%w[nmcli dev wifi connect SSID1 password newpass])
          expect { ubuntu_model._connect('SSID1', 'newpass') }.not_to raise_error
        end

        it 'activates the existing profile without direct connect when security cannot be determined' do
          setup_connect_test(profile_name: 'SSID1', old_password: 'oldpass',
            security_param: nil)

          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli connection up SSID1])
            .and_return(command_result(stdout: ''))
          expect(ubuntu_model).not_to receive(:run_command)
            .with(%w[nmcli dev wifi connect SSID1 password newpass])
          expect { ubuntu_model._connect('SSID1', 'newpass') }.not_to raise_error
        end

        it 'updates the existing profile using its saved secret type when scan security is unavailable' do
          setup_connect_test(profile_name: 'LegacyNet', old_password: 'oldpass',
            security_param: nil)
          allow(ubuntu_model).to receive(:get_security_parameter).with('LegacyNet').and_return(nil)

          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '--show-secrets', 'connection', 'show', 'LegacyNet'], raise_on_error: false)
            .and_return(command_result(stdout: '802-11-wireless-security.wep-key0:    oldpass'))
          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli connection modify LegacyNet 802-11-wireless-security.wep-key0 newpass])
            .ordered
            .and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli connection up LegacyNet])
            .ordered
            .and_return(command_result(stdout: ''))
          expect(ubuntu_model).not_to receive(:run_command)
            .with(%w[nmcli dev wifi connect LegacyNet password newpass])
          expect { ubuntu_model._connect('LegacyNet', 'newpass') }.not_to raise_error
        end

        it 'brings up existing profile when connecting without password' do
          setup_connect_test(profile_name: 'SSID3')

          expect(ubuntu_model).to receive(:run_command).with(%w[nmcli connection up SSID3])
            .and_return(command_result(stdout: ''))
          expect { ubuntu_model._connect('SSID3') }.not_to raise_error
        end

        it 'raises NetworkNotFoundError when network not in range' do
          setup_connect_test

          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli dev wifi connect SSID4 password pw])
            .and_raise(
              os_command_error(
                exitstatus: 10,
                command:    'nmcli dev wifi connect',
                text:       "Error: No network with SSID 'SSID4' found"
              )
            )

          expect { ubuntu_model._connect('SSID4', 'pw') }
            .to raise_error(WifiWand::NetworkNotFoundError, /SSID4/)
        end

        it 'raises NetworkAuthenticationError when password is wrong (secrets required)' do
          setup_connect_test

          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli dev wifi connect SecureNet password wrongpass])
            .and_raise(
              os_command_error(
                exitstatus: 4,
                command:    'nmcli dev wifi connect',
                text:       'Error: Connection activation failed: Secrets were required, but not provided'
              )
            )

          expect { ubuntu_model._connect('SecureNet', 'wrongpass') }
            .to raise_error(WifiWand::NetworkAuthenticationError, /SecureNet/)
        end

        it 'raises NetworkAuthenticationError when authentication fails' do
          setup_connect_test

          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli dev wifi connect SecureNet password badpass])
            .and_raise(
              os_command_error(
                exitstatus: 4,
                command:    'nmcli dev wifi connect',
                text:       'Error: Connection activation failed: (53) authentication failed'
              )
            )

          expect { ubuntu_model._connect('SecureNet', 'badpass') }
            .to raise_error(WifiWand::NetworkAuthenticationError, /SecureNet/)
        end

        it 'raises NetworkAuthenticationError for error code 7 (secrets issue)' do
          setup_connect_test

          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli dev wifi connect SecureNet password invalid])
            .and_raise(
              os_command_error(
                exitstatus: 7,
                command:    'nmcli dev wifi connect',
                text:       'Error: Connection activation failed: (7) No secrets provided'
              )
            )

          expect { ubuntu_model._connect('SecureNet', 'invalid') }
            .to raise_error(WifiWand::NetworkAuthenticationError, /SecureNet/)
        end

        it 'raises WifiInterfaceError when no suitable device found' do
          setup_connect_test
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlan0')

          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli dev wifi connect SSID5])
            .and_raise(
              os_command_error(
                exitstatus: 5,
                command:    'nmcli dev wifi connect',
                text:       'Error: No suitable device found'
              )
            )

          expect { ubuntu_model._connect('SSID5') }.to raise_error(WifiWand::WifiInterfaceError)
        end

        it 'raises NetworkConnectionError for generic activation failures (out of range)' do
          setup_connect_test

          expect(ubuntu_model).to receive(:run_command).with(%w[nmcli dev wifi connect WeakSignal])
            .and_raise(
              os_command_error(
                exitstatus: 4,
                command:    'nmcli dev wifi connect',
                text:       'Error: Connection activation failed'
              )
            )

          expect { ubuntu_model._connect('WeakSignal') }
            .to raise_error(WifiWand::NetworkConnectionError, /out of range/)
        end

        it 're-raises unknown errors from nmcli' do
          setup_connect_test

          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli dev wifi connect SSID6 password pw])
            .and_raise(
              os_command_error(
                exitstatus: 2,
                command:    'nmcli dev wifi connect',
                text:       'Unknown system failure'
              )
            )

          expect { ubuntu_model._connect('SSID6', 'pw') }
            .to raise_error(WifiWand::CommandExecutor::OsCommandError, /Unknown system failure/)
        end
      end

      describe '#get_security_parameter and #security_parameter' do
        it 'returns nil when nmcli scan fails' do
          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], raise_on_error: false)
            .and_raise(os_command_error(exitstatus: 1, command: 'nmcli', text: 'scan failed'))
          expect(ubuntu_model.send(:get_security_parameter, 'Any')).to be_nil
        end

        it 'returns nil for unsupported/enterprise/open security types' do
          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], raise_on_error: false)
            .and_return(command_result(stdout: 'CorpNet:802.1X'))
          expect(ubuntu_model.send(:get_security_parameter, 'CorpNet')).to be_nil
        end

        it 'delegates via #security_parameter and returns PSK param for WPA2' do
          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], raise_on_error: false)
            .and_return(command_result(stdout: 'HomeNet:WPA2'))
          expect(ubuntu_model.send(:security_parameter, 'HomeNet')).to eq('802-11-wireless-security.psk')
        end
      end

      describe '#find_best_profile_for_ssid' do
        it 'returns nil when listing connections fails' do
          expect(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .and_return(command_result(stderr: 'Error', exitstatus: 1, command: 'nmcli'))
          expect(ubuntu_model.send(:find_best_profile_for_ssid, 'SSID')).to be_nil
        end

        it 'prefers the newest profile whose configured SSID matches' do
          expect(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .and_return(command_result(
              stdout: "MySSID:802-11-wireless:100\n" \
                "Renamed Profile:802-11-wireless:300\n" \
                "MySSID 2:802-11-wireless:200\n" \
                'OtherSSID:802-11-wireless:999'
            ))
          stub_saved_profile_ssid('MySSID', 'MySSID')
          stub_saved_profile_ssid('Renamed Profile', 'MySSID')
          stub_saved_profile_ssid('MySSID 2', 'MySSID')
          stub_saved_profile_ssid('OtherSSID', 'OtherSSID')

          expect(ubuntu_model.send(:find_best_profile_for_ssid, 'MySSID')).to eq('Renamed Profile')
        end
      end

      describe 'saved profile cache' do
        it 'reuses profile discovery across one saved-password connect operation' do
          expect(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .once
            .and_return(command_result(
              stdout: "MySSID:802-11-wireless:100\nOtherSSID:802-11-wireless:200"
            ))
          stub_saved_profile_ssid('MySSID', 'MySSID')
          stub_saved_profile_ssid('OtherSSID', 'OtherSSID')
          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli connection up MySSID])
            .and_return(command_result(stdout: ''))

          allow(ubuntu_model).to receive(:wifi_on)
          allow(ubuntu_model).to receive(:connected?).and_return(false)
          allow(ubuntu_model).to receive(:connection_ready?).with('MySSID').and_return(false, true)
          expect(ubuntu_model).to receive(:preferred_network_password)
            .with('MySSID')
            .and_call_original
          expect(ubuntu_model).to receive(:_preferred_network_password)
            .with('MySSID', timeout_in_secs: :default)
            .once
            .and_return('saved-secret')
          expect(ubuntu_model).to receive(:_preferred_network_password)
            .with('MySSID')
            .once
            .and_return('saved-secret')

          ubuntu_model.connect('MySSID')
        end

        it 'reuses profile discovery across one multi-network removal operation' do
          expect(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .once
            .and_return(command_result(
              stdout: "Home Profile:802-11-wireless:100\n" \
                'Office Profile:802-11-wireless:200'
            ))
          stub_saved_profile_ssid('Home Profile', 'Home')
          stub_saved_profile_ssid('Office Profile', 'Office')
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'delete', 'Home Profile'])
            .ordered
            .and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'delete', 'Office Profile'])
            .ordered
            .and_return(command_result(stdout: ''))

          expect(ubuntu_model.remove_preferred_networks('Home', 'Office'))
            .to eq(['Home Profile', 'Office Profile'])
        end

        it 'deduplicates requested names before deleting saved profiles' do
          expect(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .once
            .and_return(command_result(stdout: 'Home Profile:802-11-wireless:100'))
          stub_saved_profile_ssid('Home Profile', 'Home')
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'delete', 'Home Profile'])
            .once
            .and_return(command_result(stdout: ''))

          expect(ubuntu_model.remove_preferred_networks('Home', 'Home')).to eq(['Home Profile'])
        end
      end

      describe '#remove_preferred_network' do
        it 'returns an empty array without deleting when network not present' do
          allow(ubuntu_model).to receive(:saved_wifi_profiles).and_return([
            saved_wifi_profile('Profile A', ssid: 'A'),
            saved_wifi_profile('Profile B', ssid: 'B'),
          ])
          expect(ubuntu_model).not_to receive(:run_command).with(/nmcli connection delete/)

          expect(ubuntu_model.remove_preferred_network('C')).to eq([])
        end

        it 'deletes an existing preferred network and returns the deleted profile name' do
          allow(ubuntu_model).to receive(:saved_wifi_profiles)
            .and_return([saved_wifi_profile('Renamed Home', ssid: 'Home')])
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'delete', 'Renamed Home'])

          expect(ubuntu_model.remove_preferred_network('Home')).to eq(['Renamed Home'])
        end

        it 'deletes only profiles whose configured SSID matches' do
          allow(ubuntu_model).to receive(:saved_wifi_profiles).and_return([
            saved_wifi_profile('MySSID', ssid: 'MySSID'),
            saved_wifi_profile('Renamed Duplicate', ssid: 'MySSID'),
            saved_wifi_profile('MySSID 2', ssid: 'OtherSSID'),
            saved_wifi_profile('MySSIDGuest', ssid: 'MySSIDGuest'),
          ])
          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli connection delete MySSID]).ordered
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'delete', 'Renamed Duplicate']).ordered

          expect(ubuntu_model.remove_preferred_network('MySSID')).to eq(['MySSID', 'Renamed Duplicate'])
        end

        it 'treats renamed profiles with matching configured SSIDs as saved' do
          allow(ubuntu_model).to receive(:saved_wifi_profiles).and_return([
            saved_wifi_profile('MySSID 1', ssid: 'MySSID'),
            saved_wifi_profile('MySSID 2', ssid: 'MySSID'),
          ])

          expect(ubuntu_model.has_preferred_network?('MySSID')).to be(true)
          expect(ubuntu_model.has_preferred_network?('OtherSSID')).to be(false)
        end

        it 'uses the saved password from the most recent matching profile' do
          allow(ubuntu_model).to receive(:saved_wifi_profiles).and_return([
            saved_wifi_profile('MySSID', ssid: 'MySSID', timestamp: 100),
            saved_wifi_profile('Renamed Fresh Profile', ssid: 'MySSID', timestamp: 300),
          ])
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '--show-secrets', 'connection', 'show',
              'Renamed Fresh Profile'], raise_on_error: false)
            .and_return(command_result(stdout: '802-11-wireless-security.psk:    fresh-secret'))

          expect(ubuntu_model.preferred_network_password('MySSID')).to eq('fresh-secret')
        end

        it 'bounds the saved password lookup when a timeout is requested' do
          allow(ubuntu_model).to receive(:saved_wifi_profiles).and_return([
            saved_wifi_profile('MySSID', ssid: 'MySSID', timestamp: 100),
            saved_wifi_profile('Renamed Fresh Profile', ssid: 'MySSID', timestamp: 300),
          ])
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '--show-secrets', 'connection', 'show',
              'Renamed Fresh Profile'], raise_on_error: false, timeout_in_secs: 0.25)
            .and_return(command_result(stdout: '802-11-wireless-security.psk:    fresh-secret'))

          expect(
            ubuntu_model.preferred_network_password('MySSID', timeout_in_secs: 0.25)
          ).to eq('fresh-secret')
        end

        it 'uses the saved WEP key from the most recent matching profile' do
          allow(ubuntu_model).to receive(:saved_wifi_profiles).and_return([
            saved_wifi_profile('MySSID', ssid: 'MySSID', timestamp: 100),
            saved_wifi_profile('Renamed Fresh Profile', ssid: 'MySSID', timestamp: 300),
          ])
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '--show-secrets', 'connection', 'show',
              'Renamed Fresh Profile'], raise_on_error: false)
            .and_return(command_result(stdout: '802-11-wireless-security.wep-key0:    fresh-wep-key'))

          expect(ubuntu_model.preferred_network_password('MySSID')).to eq('fresh-wep-key')
        end

        it 'does not treat a duplicate-looking profile name as an SSID match' do
          allow(ubuntu_model).to receive(:saved_wifi_profiles).and_return([
            saved_wifi_profile('MySSID 1', ssid: 'MySSID'),
          ])

          expect { ubuntu_model.preferred_network_password('MySSID 1') }
            .to raise_error(PreferredNetworkNotFoundError)
        end

        it 'does not delete non-Wi-Fi profile even if name matches' do
          allow(ubuntu_model).to receive(:saved_wifi_profiles).and_return([
            saved_wifi_profile('MyWifiNetwork', ssid: 'MyWifiNetwork'),
          ])
          expect(ubuntu_model).not_to receive(:run_command).with(/nmcli connection delete/)

          expect(ubuntu_model.remove_preferred_network('Wired connection 1')).to eq([])
        end
      end

      describe 'saved password connect flow' do
        it 'passes the saved password from the best matching profile into _connect' do
          allow(ubuntu_model).to receive(:wifi_on)
          allow(ubuntu_model.connection_manager).to receive(:wait_for_connection_activation)
          allow(ubuntu_model).to receive(:connection_ready?).and_return(false, true)
          allow(ubuntu_model).to receive(:connected_network_name).and_return(nil, 'MySSID')
          allow(ubuntu_model).to receive(:saved_wifi_profiles).and_return([
            saved_wifi_profile('MySSID', ssid: 'MySSID', timestamp: 100),
            saved_wifi_profile('Renamed Fresh Profile', ssid: 'MySSID', timestamp: 300),
          ])
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '--show-secrets', 'connection', 'show',
              'Renamed Fresh Profile'], raise_on_error: false)
            .and_return(command_result(stdout: '802-11-wireless-security.psk:    fresh-secret'))
          expect(ubuntu_model).to receive(:_connect).with('MySSID', 'fresh-secret')

          ubuntu_model.connect('MySSID')
          expect(ubuntu_model.last_connection_used_saved_password?).to be true
        end

        it 'passes the saved WEP key from the best matching profile into _connect' do
          allow(ubuntu_model).to receive(:wifi_on)
          allow(ubuntu_model.connection_manager).to receive(:wait_for_connection_activation)
          allow(ubuntu_model).to receive(:connection_ready?).and_return(false, true)
          allow(ubuntu_model).to receive(:connected_network_name).and_return(nil, 'MySSID')
          allow(ubuntu_model).to receive(:saved_wifi_profiles).and_return([
            saved_wifi_profile('MySSID', ssid: 'MySSID', timestamp: 100),
            saved_wifi_profile('Renamed Fresh Profile', ssid: 'MySSID', timestamp: 300),
          ])
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '--show-secrets', 'connection', 'show',
              'Renamed Fresh Profile'], raise_on_error: false)
            .and_return(command_result(stdout: '802-11-wireless-security.wep-key0:    fresh-wep-key'))
          expect(ubuntu_model).to receive(:_connect).with('MySSID', 'fresh-wep-key')

          ubuntu_model.connect('MySSID')
          expect(ubuntu_model.last_connection_used_saved_password?).to be true
        end
      end

      describe '#_disconnect' do
        it 'returns nil when disconnect succeeds' do
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlan0')
          expect(ubuntu_model).to receive(:run_command).with(%w[nmcli dev disconnect wlan0])
            .and_return(command_result(stdout: ''))
          expect(ubuntu_model.send(:_disconnect)).to be_nil
        end
      end

      describe '#nameservers with active connection' do
        it 'returns connection-specific nameservers when present' do
          allow(ubuntu_model).to receive_messages(
            active_connection_profile_name: 'Conn1',
            _connected_network_name:        'SSID-Conn1'
          )
          expect(ubuntu_model).to receive(:nameservers_from_connection).with('Conn1').and_return(['1.1.1.1'])
          expect(ubuntu_model.nameservers).to eq(['1.1.1.1'])
        end

        it 'prefers the active profile name over the SSID when resolving DNS' do
          allow(ubuntu_model).to receive_messages(
            active_connection_profile_name: 'RenamedProfile',
            _connected_network_name:        'SSID-RenamedProfile'
          )
          expect(ubuntu_model).to receive(:nameservers_from_connection).with('RenamedProfile')
            .and_return(['9.9.9.9'])
          expect(ubuntu_model.nameservers).to eq(['9.9.9.9'])
        end

        it 'falls back to resolv.conf when connection has no DNS' do
          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return('Conn2')
          expect(ubuntu_model).to receive(:nameservers_from_connection).with('Conn2').and_return([])
          expect(ubuntu_model).to receive(:nameservers_using_resolv_conf).and_return(['9.9.9.9'])
          expect(ubuntu_model.nameservers).to eq(['9.9.9.9'])
        end

        it 'uses SSID as a fallback when profile name is unavailable' do
          allow(ubuntu_model).to receive_messages(
            active_connection_profile_name: nil,
            _connected_network_name:        'FallbackSSID'
          )
          expect(ubuntu_model).to receive(:nameservers_from_connection).with('FallbackSSID')
            .and_return(['4.4.4.4'])
          expect(ubuntu_model.nameservers).to eq(['4.4.4.4'])
        end

        it 'does not query a connection profile for the no-connection placeholder' do
          allow(ubuntu_model).to receive_messages(
            wifi_interface:          'wlp3s0',
            _connected_network_name: nil
          )
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '-t', '-f', 'GENERAL.CONNECTION', 'dev', 'show',
              'wlp3s0'], raise_on_error: false)
            .and_return(command_result(stdout: 'GENERAL.CONNECTION:--'))

          expect(ubuntu_model).not_to receive(:nameservers_from_connection)
          expect(ubuntu_model).to receive(:nameservers_using_resolv_conf).and_return(['8.8.8.8'])
          expect(ubuntu_model.nameservers).to eq(['8.8.8.8'])
        end
      end

      describe '#open_resource' do
        it 'invokes xdg-open on the given URL' do
          expect(ubuntu_model).to receive(:run_command).with(['xdg-open', 'https://example.com'])
            .and_return(command_result(stdout: ''))
          ubuntu_model.open_resource('https://example.com')
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
          expect(ubuntu_model).to receive(:run_command).with(%w[nmcli connection show ConnX],
            raise_on_error: false)
            .and_return(command_result(stdout: nmcli_output))
          expect(ubuntu_model.send(:nameservers_from_connection, 'ConnX')).to eq(['1.1.1.1', '9.9.9.9'])
        end

        it 'deduplicates DNS servers repeated in configured and runtime nmcli fields' do
          nmcli_output = <<~OUT
            connection.id:                   ConnDup
            ipv4.dns[1]:                     1.1.1.1
            IP4.DNS[1]:                      1.1.1.1
          OUT
          expect(ubuntu_model).to receive(:run_command).with(%w[nmcli connection show ConnDup],
            raise_on_error: false)
            .and_return(command_result(stdout: nmcli_output))
          expect(ubuntu_model.send(:nameservers_from_connection, 'ConnDup')).to eq(['1.1.1.1'])
        end

        it 'returns empty array when nmcli connection show fails' do
          expect(ubuntu_model).to receive(:run_command).with(%w[nmcli connection show ConnY],
            raise_on_error: false)
            .and_raise(os_command_error(exitstatus: 1, command: 'nmcli connection show', text: 'failed'))
          expect(ubuntu_model.send(:nameservers_from_connection, 'ConnY')).to eq([])
        end

        it 'parses IPv6 DNS servers without truncating at colons' do
          nmcli_output = <<~OUT
            connection.id:                   ConnZ
            ipv6.dns[1]:                     2606:4700:4700::1111
            IP6.DNS[2]:                      2606:4700:4700::1001
            some.other:                      value
          OUT
          expect(ubuntu_model).to receive(:run_command).with(%w[nmcli connection show ConnZ],
            raise_on_error: false)
            .and_return(command_result(stdout: nmcli_output))
          expect(ubuntu_model.send(:nameservers_from_connection, 'ConnZ'))
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
          expect(ubuntu_model).to receive(:run_command).with(%w[nmcli connection show ConnM],
            raise_on_error: false)
            .and_return(command_result(stdout: nmcli_output))
          result = ubuntu_model.send(:nameservers_from_connection, 'ConnM')
          expect(result).to include('1.1.1.1', '9.9.9.9', '2606:4700:4700::1111', '2001:4860:4860::8888')
          expect(result.length).to eq(4)
        end
      end

      describe '#validate_os_preconditions' do
        it 'returns :ok when all required commands are available' do
          allow(ubuntu_model).to receive(:command_available?).with('iw')
            .and_return(command_result(stdout: true))
          allow(ubuntu_model).to receive(:command_available?).with('nmcli').and_return(true)
          allow(ubuntu_model).to receive(:command_available?).with('ip').and_return(true)

          expect(ubuntu_model.validate_os_preconditions).to eq(:ok)
        end

        it 'raises dependency guidance instead of a raw exception when PATH is unset' do
          original_path = ENV['PATH']
          ENV.delete('PATH')

          expect do
            ubuntu_model.validate_os_preconditions
          end.to raise_error(WifiWand::CommandNotFoundError, /sudo apt install/)
        ensure
          original_path ? (ENV['PATH'] = original_path) : ENV.delete('PATH')
        end

        it 'raises CommandNotFoundError when iw is missing' do
          allow(ubuntu_model).to receive(:command_available?).with('iw').and_return(false)
          allow(ubuntu_model).to receive(:command_available?).with('nmcli').and_return(true)
          allow(ubuntu_model).to receive(:command_available?).with('ip').and_return(true)

          expect { ubuntu_model.validate_os_preconditions }
            .to raise_error(WifiWand::CommandNotFoundError, /iw.*install.*sudo apt install iw/)
        end

        it 'raises CommandNotFoundError when nmcli is missing' do
          allow(ubuntu_model).to receive(:command_available?).with('iw').and_return(true)
          allow(ubuntu_model).to receive(:command_available?).with('nmcli').and_return(false)
          allow(ubuntu_model).to receive(:command_available?).with('ip').and_return(true)

          expect { ubuntu_model.validate_os_preconditions }
            .to raise_error(WifiWand::CommandNotFoundError,
              /nmcli.*install.*sudo apt install network-manager/)
        end

        it 'raises CommandNotFoundError when ip is missing' do
          allow(ubuntu_model).to receive(:command_available?).with('iw').and_return(true)
          allow(ubuntu_model).to receive(:command_available?).with('nmcli').and_return(true)
          allow(ubuntu_model).to receive(:command_available?).with('ip').and_return(false)

          expect { ubuntu_model.validate_os_preconditions }
            .to raise_error(WifiWand::CommandNotFoundError, /ip.*install.*sudo apt install iproute2/)
        end

        it 'raises CommandNotFoundError when iw and nmcli are missing' do
          allow(ubuntu_model).to receive(:command_available?).with('iw').and_return(false)
          allow(ubuntu_model).to receive(:command_available?).with('nmcli').and_return(false)
          allow(ubuntu_model).to receive(:command_available?).with('ip').and_return(true)

          expect { ubuntu_model.validate_os_preconditions }
            .to raise_error(WifiWand::CommandNotFoundError, /iw.*nmcli/)
        end

        it 'raises CommandNotFoundError when iw and ip are missing' do
          allow(ubuntu_model).to receive(:command_available?).with('iw').and_return(false)
          allow(ubuntu_model).to receive(:command_available?).with('nmcli').and_return(true)
          allow(ubuntu_model).to receive(:command_available?).with('ip').and_return(false)

          expect { ubuntu_model.validate_os_preconditions }
            .to raise_error(WifiWand::CommandNotFoundError, /iw.*ip/)
        end

        it 'raises CommandNotFoundError when nmcli and ip are missing' do
          allow(ubuntu_model).to receive(:command_available?).with('iw').and_return(true)
          allow(ubuntu_model).to receive(:command_available?).with('nmcli').and_return(false)
          allow(ubuntu_model).to receive(:command_available?).with('ip').and_return(false)

          expect { ubuntu_model.validate_os_preconditions }
            .to raise_error(WifiWand::CommandNotFoundError, /nmcli.*ip/)
        end

        it 'raises CommandNotFoundError when iw, nmcli, and ip are missing' do
          allow(ubuntu_model).to receive(:command_available?).with('iw').and_return(false)
          allow(ubuntu_model).to receive(:command_available?).with('nmcli').and_return(false)
          allow(ubuntu_model).to receive(:command_available?).with('ip').and_return(false)

          expect { ubuntu_model.validate_os_preconditions }
            .to raise_error(WifiWand::CommandNotFoundError, /iw.*nmcli.*ip/)
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

          allow(ubuntu_model).to receive(:run_command)
            .with(%w[iw dev], timeout_in_secs: nil)
            .and_return(command_result(stdout: iw_output))

          expect(ubuntu_model.probe_wifi_interface).to eq('wlp3s0')
        end

        it 'skips p2p-dev virtual interface and returns the managed interface' do
          iw_output = <<~IW_OUTPUT
            phy#0
                Interface p2p-dev-wlp3s0
                type P2P-device
                Interface wlp3s0
                type managed
          IW_OUTPUT

          allow(ubuntu_model).to receive(:run_command)
            .with(%w[iw dev], timeout_in_secs: nil)
            .and_return(command_result(stdout: iw_output))

          expect(ubuntu_model.probe_wifi_interface).to eq('wlp3s0')
        end

        it 'returns nil when no managed interfaces found' do
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[iw dev], timeout_in_secs: nil)
            .and_return(command_result(stdout: "phy#0\n    type managed"))

          expect(ubuntu_model.probe_wifi_interface).to be_nil
        end

        it 'handles command failures gracefully' do
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[iw dev], timeout_in_secs: nil)
            .and_raise(os_command_error(exitstatus: 1, command: 'iw dev', text: 'Command failed'))

          expect { ubuntu_model.probe_wifi_interface }
            .to raise_error(WifiWand::CommandExecutor::OsCommandError)
        end
      end

      describe '#preferred_networks' do
        it 'returns list of saved Wi-Fi network SSIDs' do
          nmcli_output = <<~OUT.chomp
            Renamed profile 1:802-11-wireless:100
            TestNetwork-2:802-11-wireless:200
            Wired connection 1:ethernet:300
          OUT
          allow(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .and_return(command_result(stdout: nmcli_output))
          stub_saved_profile_ssid('Renamed profile 1', 'TestNetwork-1')
          stub_saved_profile_ssid('TestNetwork-2', 'TestNetwork-2')

          result = ubuntu_model.preferred_networks
          expect(result).to be_an(Array)
          expect(result).to include('TestNetwork-1', 'TestNetwork-2')
          expect(result).not_to include('Renamed profile 1')
          expect(result).not_to include('Wired connection 1')
        end

        it 'looks up each Wi-Fi profile SSID from the profile details' do
          nmcli_output = <<~OUT.chomp
            Renamed profile 1:802-11-wireless:100
            TestNetwork-2:802-11-wireless:200
          OUT
          allow(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .and_return(command_result(stdout: nmcli_output))
          expect(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_ssid_fields('Renamed profile 1'), raise_on_error: false)
            .and_return(command_result(stdout: '802-11-wireless.ssid:TestNetwork-1'))
          expect(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_ssid_fields('TestNetwork-2'), raise_on_error: false)
            .and_return(command_result(stdout: '802-11-wireless.ssid:TestNetwork-2'))

          expect(ubuntu_model.preferred_networks).to eq(%w[TestNetwork-1 TestNetwork-2])
        end

        it 'handles Wi-Fi profile detail lookups that finish out of order' do
          stub_const('WifiWand::Platforms::Ubuntu::Model::SAVED_WIFI_PROFILE_SSID_LOOKUP_WORKERS', 2)
          nmcli_output = <<~OUT.chomp
            Slow profile:802-11-wireless:100
            Fast profile:802-11-wireless:200
            Wired connection:ethernet:300
          OUT
          slow_started = Queue.new
          release_slow = Queue.new
          completion_order = Queue.new

          allow(ubuntu_model).to receive(:run_command) do |command, raise_on_error: true|
            if command == nmcli_saved_profile_summary_fields && raise_on_error == false
              command_result(stdout: nmcli_output)
            elsif command[0, 5] == %w[nmcli -t -f 802-11-wireless.ssid connection] &&
                command[5] == 'show' && raise_on_error == false
              profile_name = command[6]
              if profile_name == 'Slow profile'
                slow_started << true
                release_slow.pop
                completion_order << profile_name
                command_result(stdout: '802-11-wireless.ssid:SlowNetwork')
              else
                completion_order << profile_name
                command_result(stdout: '802-11-wireless.ssid:FastNetwork')
              end
            else
              command_result(stdout: '')
            end
          end

          result_thread = Thread.new { ubuntu_model.preferred_networks }
          Timeout.timeout(1) { slow_started.pop }
          expect(Timeout.timeout(1) { completion_order.pop }).to eq('Fast profile')
          release_slow << true

          expect(result_thread.value).to eq(%w[FastNetwork SlowNetwork])
        end

        it 'bounds concurrent Wi-Fi profile detail lookups' do
          worker_count = 3
          stub_const('WifiWand::Platforms::Ubuntu::Model::SAVED_WIFI_PROFILE_SSID_LOOKUP_WORKERS',
            worker_count)
          profile_names = Array.new(worker_count + 4) { |index| "Profile #{index}" }
          nmcli_output = profile_names.map do |profile_name|
            "#{profile_name}:802-11-wireless:100"
          end.join("\n")
          entered_detail_lookup = Queue.new
          release_detail_lookup = Queue.new
          concurrency_mutex = Mutex.new
          active_detail_lookups = 0
          max_detail_lookups = 0

          allow(ubuntu_model).to receive(:run_command) do |command, raise_on_error: true|
            if command == nmcli_saved_profile_summary_fields && raise_on_error == false
              command_result(stdout: nmcli_output)
            elsif command[0, 5] == %w[nmcli -t -f 802-11-wireless.ssid connection] &&
                command[5] == 'show' && raise_on_error == false
              profile_name = command[6]
              concurrency_mutex.synchronize do
                active_detail_lookups += 1
                max_detail_lookups = [max_detail_lookups, active_detail_lookups].max
              end
              entered_detail_lookup << true
              release_detail_lookup.pop
              concurrency_mutex.synchronize { active_detail_lookups -= 1 }
              command_result(stdout: "802-11-wireless.ssid:#{profile_name}")
            else
              command_result(stdout: '')
            end
          end

          result_thread = Thread.new { ubuntu_model.preferred_networks }
          Timeout.timeout(1) { worker_count.times { entered_detail_lookup.pop } }
          expect(max_detail_lookups).to eq(worker_count)

          profile_names.length.times { release_detail_lookup << true }
          expect(result_thread.value).to eq(profile_names)
        end

        it 'deduplicates duplicate SSIDs from profile details' do
          nmcli_output = <<~OUT.chomp
            TestNetwork:802-11-wireless:100
            TestNetwork 1:802-11-wireless:200
          OUT
          allow(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .and_return(command_result(stdout: nmcli_output))
          expect(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_ssid_fields('TestNetwork'), raise_on_error: false)
            .and_return(command_result(stdout: '802-11-wireless.ssid:TestNetwork'))
          expect(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_ssid_fields('TestNetwork 1'), raise_on_error: false)
            .and_return(command_result(stdout: '802-11-wireless.ssid:TestNetwork'))

          expect(ubuntu_model.preferred_networks).to eq(['TestNetwork'])
        end

        it 'skips a Wi-Fi profile when the fallback lookup returns an empty SSID' do
          allow(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .and_return(command_result(stdout: 'Empty SSID profile:802-11-wireless:100'))
          allow(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_ssid_fields('Empty SSID profile'), raise_on_error: false)
            .and_return(command_result(stdout: '802-11-wireless.ssid:'))

          expect(ubuntu_model.preferred_networks).to eq([])
        end

        it 'skips only the Wi-Fi profile whose detail lookup fails' do
          nmcli_output = <<~OUT.chomp
            Working profile:802-11-wireless:100
            Broken profile:802-11-wireless:200
          OUT
          allow(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .and_return(command_result(stdout: nmcli_output))
          stub_saved_profile_ssid('Working profile', 'WorkingNetwork')
          allow(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_ssid_fields('Broken profile'), raise_on_error: false)
            .and_raise(WifiWand::CommandSpawnError.new(command: 'nmcli', reason: 'spawn failed'))

          expect(ubuntu_model.preferred_networks).to eq(['WorkingNetwork'])
        end

        it 'returns empty array when no Wi-Fi connections exist' do
          nmcli_output = "Wired connection 1:ethernet:100\nVPN profile:vpn:200"
          allow(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .and_return(command_result(stdout: nmcli_output))

          expect(ubuntu_model.preferred_networks).to eq([])
        end

        it 'returns empty array when the saved profile summary query fails' do
          allow(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .and_return(command_result(stderr: 'network manager unavailable', exitstatus: 10))

          expect(ubuntu_model.preferred_networks).to eq([])
        end

        it 'returns empty array when nmcli cannot be found' do
          allow(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .and_raise(WifiWand::CommandNotFoundError, 'nmcli')

          expect(ubuntu_model.preferred_networks).to eq([])
        end

        it 'returns empty array when the saved profile query cannot start' do
          allow(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .and_raise(WifiWand::CommandSpawnError.new(command: 'nmcli', reason: 'spawn failed'))

          expect(ubuntu_model.preferred_networks).to eq([])
        end

        it 'skips a Wi-Fi profile when its fallback SSID lookup cannot start' do
          allow(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .and_return(command_result(stdout: 'Saved profile:802-11-wireless:100'))
          allow(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_ssid_fields('Saved profile'), raise_on_error: false)
            .and_raise(WifiWand::CommandSpawnError.new(command: 'nmcli', reason: 'spawn failed'))

          expect(ubuntu_model.preferred_networks).to eq([])
        end

        it 'filters out empty lines and non-Wi-Fi connections from output' do
          nmcli_output = <<~OUT.chomp
            TestNetwork:802-11-wireless:100


            Wired connection:ethernet:200
            VPN profile:vpn:300
          OUT
          allow(ubuntu_model).to receive(:run_command)
            .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
            .and_return(command_result(stdout: nmcli_output))
          stub_saved_profile_ssid('TestNetwork', 'TestNetwork')

          result = ubuntu_model.preferred_networks
          expect(result).to eq(['TestNetwork'])
        end
      end

      describe '#nameservers' do
        it 'returns nameservers from resolv.conf' do
          allow(ubuntu_model).to receive_messages(
            active_connection_profile_name: nil,
            _connected_network_name:        nil,
            nameservers_using_resolv_conf:  ['8.8.8.8', '8.8.4.4']
          )

          expect(ubuntu_model.nameservers).to eq(['8.8.8.8', '8.8.4.4'])
        end

        it 'returns empty array when no nameservers configured' do
          allow(ubuntu_model).to receive_messages(
            active_connection_profile_name: nil,
            _connected_network_name:        nil,
            nameservers_using_resolv_conf:  []
          )

          expect(ubuntu_model.nameservers).to eq([])
        end
      end

      describe '#_ipv4_addresses' do
        it 'returns IPv4 addresses from interface' do
          ip_output = <<~OUT.chomp
            2: wlp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP>
            inet 192.168.1.100/24 brd 192.168.1.255 scope global dynamic noprefixroute wlp3s0
          OUT
          wifi_interface = 'wlp3s0'

          allow(ubuntu_model).to receive(:wifi_interface).and_return(wifi_interface)
          allow(ubuntu_model).to receive(:run_command)
            .with(['ip', '-4', 'addr', 'show', wifi_interface], raise_on_error: false)
            .and_return(command_result(stdout: ip_output))

          expect(ubuntu_model.send(:_ipv4_addresses)).to eq(['192.168.1.100'])
        end

        it 'returns an empty array when no IPv4 address is assigned' do
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          allow(ubuntu_model).to receive(:run_command)
            .with(['ip', '-4', 'addr', 'show', 'wlp3s0'], raise_on_error: false)
            .and_return(command_result(stdout: ''))

          expect(ubuntu_model.send(:_ipv4_addresses)).to eq([])
        end

        it 'returns multiple IPv4 addresses from the interface' do
          ip_output = <<~OUT.chomp
            2: wlp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP>
            inet 192.168.1.100/24 brd 192.168.1.255 scope global
            inet 10.0.0.50/24 brd 10.0.0.255 scope global secondary
          OUT
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          allow(ubuntu_model).to receive(:run_command)
            .with(['ip', '-4', 'addr', 'show', 'wlp3s0'], raise_on_error: false)
            .and_return(command_result(stdout: ip_output))

          expect(ubuntu_model.send(:_ipv4_addresses)).to eq(['192.168.1.100', '10.0.0.50'])
        end
      end

      describe '#_ipv6_addresses' do
        it 'returns IPv6 addresses from interface' do
          ip_output = <<~OUT.chomp
            2: wlp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP>
            inet6 2001:db8::100/64 scope global dynamic noprefixroute
          OUT
          wifi_interface = 'wlp3s0'

          allow(ubuntu_model).to receive(:wifi_interface).and_return(wifi_interface)
          allow(ubuntu_model).to receive(:run_command)
            .with(['ip', '-6', 'addr', 'show', wifi_interface], raise_on_error: false)
            .and_return(command_result(stdout: ip_output))

          expect(ubuntu_model.send(:_ipv6_addresses)).to eq(['2001:db8::100'])
        end

        it 'returns an empty array when no IPv6 address is assigned' do
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          allow(ubuntu_model).to receive(:run_command)
            .with(['ip', '-6', 'addr', 'show', 'wlp3s0'], raise_on_error: false)
            .and_return(command_result(stdout: ''))

          expect(ubuntu_model.send(:_ipv6_addresses)).to eq([])
        end

        it 'returns multiple IPv6 addresses from the interface' do
          ip_output = <<~OUT.chomp
            2: wlp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP>
            inet6 fe80::1/64 scope link
            inet6 2001:db8::100/64 scope global dynamic
          OUT
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          allow(ubuntu_model).to receive(:run_command)
            .with(['ip', '-6', 'addr', 'show', 'wlp3s0'], raise_on_error: false)
            .and_return(command_result(stdout: ip_output))

          expect(ubuntu_model.send(:_ipv6_addresses)).to eq(['fe80::1', '2001:db8::100'])
        end
      end

      describe '#mac_address' do
        it 'returns MAC address of wifi interface' do
          mac_output = <<~OUT.chomp
            2: wlp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP>
            link/ether aa:bb:cc:dd:ee:ff brd ff:ff:ff:ff:ff:ff
          OUT
          wifi_interface = 'wlp3s0'

          allow(ubuntu_model).to receive(:wifi_interface).and_return(wifi_interface)
          allow(ubuntu_model).to receive(:run_command)
            .with(['ip', 'link', 'show', wifi_interface], raise_on_error: false)
            .and_return(command_result(stdout: mac_output))

          expect(ubuntu_model.mac_address).to eq('aa:bb:cc:dd:ee:ff')
        end

        it 'returns nil when no MAC address found' do
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[ip link show wlp3s0], raise_on_error: false)
            .and_return(command_result(stdout: ''))

          expect(ubuntu_model.mac_address).to be_nil
        end
      end

      describe '#connection_security_type' do
        let(:network_name) { 'TestNetwork' }

        before do
          allow(ubuntu_model).to receive(:_connected_network_name).and_return(network_name)
        end

        [
          ['WPA2',                        '*:TestNetwork:WPA2',      'WPA2'],
          ['WPA3',                        '*:TestNetwork:WPA3',      'WPA3'],
          ['WPA',                         '*:TestNetwork:WPA',       'WPA'],
          ['WPA1',                        '*:TestNetwork:WPA1',      'WPA'],
          ['WEP',                         '*:TestNetwork:WEP',       'WEP'],
          ['Mixed WPA',                   '*:TestNetwork:WPA1 WPA2', 'WPA2'],
          ['empty security (open)',       '*:TestNetwork:',          'NONE'],
          ['placeholder security (open)', '*:TestNetwork:--',        'NONE'],
          ['unknown security',            '*:TestNetwork:UNKNOWN',   nil],
        ].each do |description, nmcli_line, expected|
          it "returns #{expected || 'nil'} for #{description}" do
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli -t -f IN-USE,SSID,SECURITY dev wifi list], raise_on_error: false)
              .and_return(command_result(stdout: nmcli_line))

            expect(ubuntu_model.connection_security_type).to eq(expected)
          end
        end

        it 'uses the active scan row when duplicate SSIDs advertise different security' do
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli -t -f IN-USE,SSID,SECURITY dev wifi list], raise_on_error: false)
            .and_return(command_result(stdout: ":TestNetwork:\n*:TestNetwork:WPA2"))

          expect(ubuntu_model.connection_security_type).to eq('WPA2')
        end

        it 'returns nil when not connected to any network' do
          allow(ubuntu_model).to receive(:_connected_network_name).and_return(nil)

          expect(ubuntu_model.connection_security_type).to be_nil
        end

        it 'returns nil when network not found in scan results' do
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli -t -f IN-USE,SSID,SECURITY dev wifi list], raise_on_error: false)
            .and_return(command_result(stdout: '*:OtherNetwork:WPA2'))

          expect(ubuntu_model.connection_security_type).to be_nil
        end

        it 'returns nil when nmcli command fails' do
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli -t -f IN-USE,SSID,SECURITY dev wifi list], raise_on_error: false)
            .and_raise(os_command_error(exitstatus: 1, command: 'nmcli', text: 'Command failed'))

          expect(ubuntu_model.connection_security_type).to be_nil
        end
      end

      describe '#network_hidden?' do
        let(:network_name) { 'TestNetwork' }
        let(:profile_name) { 'TestNetwork' }

        before do
          allow(ubuntu_model).to receive_messages(
            _connected_network_name:        network_name,
            active_connection_profile_name: profile_name
          )
        end

        it 'returns true when connection profile has hidden=yes' do
          hidden_output = "802-11-wireless.hidden:yes\n"
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '-t', '-f', '802-11-wireless.hidden', 'connection', 'show',
              profile_name], raise_on_error: false)
            .and_return(command_result(stdout: hidden_output))

          expect(ubuntu_model.network_hidden?).to be true
        end

        it 'returns false when connection profile has hidden=no' do
          visible_output = "802-11-wireless.hidden:no\n"
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '-t', '-f', '802-11-wireless.hidden', 'connection', 'show',
              profile_name], raise_on_error: false)
            .and_return(command_result(stdout: visible_output))

          expect(ubuntu_model.network_hidden?).to be false
        end

        it 'returns false when not connected to any network' do
          allow(ubuntu_model).to receive(:_connected_network_name).and_return(nil)

          expect(ubuntu_model.network_hidden?).to be false
        end

        it 'returns false when hidden line is not found in output' do
          other_output = "802-11-wireless.ssid:TestNetwork\n"
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '-t', '-f', '802-11-wireless.hidden', 'connection', 'show',
              profile_name], raise_on_error: false)
            .and_return(command_result(stdout: other_output))

          expect(ubuntu_model.network_hidden?).to be false
        end

        it 'returns false when nmcli command fails' do
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '-t', '-f', '802-11-wireless.hidden', 'connection', 'show',
              profile_name], raise_on_error: false)
            .and_raise(os_command_error(exitstatus: 1, command: 'nmcli', text: 'Command failed'))

          expect(ubuntu_model.network_hidden?).to be false
        end

        it 'uses network name when active connection profile is nil' do
          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(nil)
          hidden_output = "802-11-wireless.hidden:yes\n"
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '-t', '-f', '802-11-wireless.hidden', 'connection', 'show',
              network_name], raise_on_error: false)
            .and_return(command_result(stdout: hidden_output))

          expect(ubuntu_model.network_hidden?).to be true
        end
      end

      describe '#default_interface' do
        it 'returns interface from default route' do
          route_output = 'default via 192.168.1.1 dev wlp3s0 proto dhcp metric 600'
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[ip route show default], raise_on_error: false)
            .and_return(command_result(stdout: route_output))

          expect(ubuntu_model.default_interface).to eq('wlp3s0')
        end

        it 'returns nil when ip route command fails' do
          expect(ubuntu_model).to receive(:run_command).with(%w[ip route show default],
            raise_on_error: false)
            .and_raise(os_command_error(exitstatus: 1, command: 'ip route show default', text: 'failed'))
          expect(ubuntu_model.default_interface).to be_nil
        end

        it 'returns nil when no default route exists' do
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[ip route show default], raise_on_error: false)
            .and_return(command_result(stdout: ''))

          expect(ubuntu_model.default_interface).to be_nil
        end
      end

      # Happy path testing for core functionality
      describe '#wifi_on?' do
        it 'correctly detects wifi enabled state' do
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli radio wifi], raise_on_error: false)
            .and_return(command_result(stdout: 'enabled'))

          expect(ubuntu_model.wifi_on?).to be(true)
        end

        it 'correctly detects wifi disabled state' do
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli radio wifi], raise_on_error: false)
            .and_return(command_result(stdout: 'disabled'))

          expect(ubuntu_model.wifi_on?).to be(false)
        end

        it 'raises a command error when nmcli cannot report radio state' do
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli radio wifi], raise_on_error: false)
            .and_return(command_result(
              stderr: 'aborted', exitstatus: nil, termsig: 6, command: nmcli_radio_cmd
            ))

          expect { ubuntu_model.wifi_on? }
            .to raise_error(WifiWand::CommandExecutor::OsCommandError, /aborted/)
        end
      end

      describe '#connected?' do
        it 'returns false immediately when wifi is off without querying active connections' do
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli radio wifi], raise_on_error: false)
            .and_return(command_result(stdout: 'disabled'))

          expect(ubuntu_model).not_to receive(:run_command)
            .with(['nmcli', '-t', '-f', 'DEVICE', 'connection', 'show', '--active'], raise_on_error: false)

          expect(ubuntu_model.connected?).to be(false)
        end

        it 'returns false when wifi is on and the wifi interface is not in the active connection list' do
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli radio wifi], raise_on_error: false)
            .and_return(command_result(stdout: 'enabled'))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '-t', '-f', 'DEVICE', 'connection', 'show', '--active'], raise_on_error: false)
            .and_return(command_result(stdout: 'lo'))

          expect(ubuntu_model.connected?).to be(false)
        end

        it 'returns true when wifi is on and the wifi interface has an active connection' do
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli radio wifi], raise_on_error: false)
            .and_return(command_result(stdout: 'enabled'))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '-t', '-f', 'DEVICE', 'connection', 'show', '--active'], raise_on_error: false)
            .and_return(command_result(stdout: "wlp3s0\nlo"))

          expect(ubuntu_model.connected?).to be(true)
        end
      end

      describe '#status_network_identity' do
        it 'validates OS preconditions before caching a probed status interface' do
          error = WifiWand::CommandNotFoundError.new(
            'nmcli (install: sudo apt install network-manager)'
          )
          expect(ubuntu_model).to receive(:validate_os_preconditions).and_raise(error)
          expect(ubuntu_model).not_to receive(:probe_wifi_interface)

          expect { ubuntu_model.status_network_identity(timeout_in_secs: 0.5) }
            .to raise_error(WifiWand::CommandNotFoundError, /nmcli.*sudo apt install network-manager/)
          expect(ubuntu_model.instance_variable_get(:@wifi_interface)).to be_nil
        end

        it 'passes the remaining status budget into each OS command' do
          ubuntu_model.wifi_interface = 'wlp3s0'
          status_timeout = be_between(0, 0.5).exclusive

          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli radio wifi], raise_on_error: false, timeout_in_secs: status_timeout)
            .ordered
            .and_return(command_result(stdout: 'enabled'))
          expect(ubuntu_model).to receive(:run_command)
            .with(
              ['nmcli', '-t', '-f', 'DEVICE', 'connection', 'show', '--active'],
              raise_on_error:  false,
              timeout_in_secs: status_timeout
            )
            .ordered
            .and_return(command_result(stdout: "wlp3s0\nlo"))
          expect(ubuntu_model).to receive(:run_command)
            .with(%w[iw dev wlp3s0 link], raise_on_error: false, timeout_in_secs: status_timeout)
            .ordered
            .and_return(command_result(stdout: "Connected to aa:bb:cc\nSSID: HomeNetwork\n"))
          expect(ubuntu_model).to receive(:run_command)
            .with(
              ['nmcli', '-t', '-f', 'IN-USE,SIGNAL', 'dev', 'wifi', 'list', '--rescan', 'no'],
              raise_on_error:  false,
              timeout_in_secs: status_timeout
            )
            .ordered
            .and_return(command_result(stdout: "*:72\n"))

          expect(ubuntu_model.status_network_identity(timeout_in_secs: 0.5)).to eq(
            connected:      true,
            network_name:   'HomeNetwork',
            signal_quality: WifiWand::SignalQuality.new(value: 72, unit: :percent)
          )
        end

        it 'does not treat a failed nmcli radio probe as a disconnected state' do
          ubuntu_model.wifi_interface = 'wlp3s0'

          expect(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli radio wifi], raise_on_error: false, timeout_in_secs: be_between(0, 0.5).exclusive)
            .and_return(command_result(
              stderr: 'aborted', exitstatus: nil, termsig: 6, command: nmcli_radio_cmd
            ))

          expect { ubuntu_model.status_network_identity(timeout_in_secs: 0.5) }
            .to raise_error(WifiWand::CommandExecutor::OsCommandError, /aborted/)
        end
      end

      describe '#available_network_names' do
        it 'returns sorted list of available networks by signal strength' do
          nmcli_output = "TestNet1:75\nStrongNet:90\nWeakNet:25\nTestNet2:80"
          # Mock wifi_on? check that happens in BaseModel#available_network_names
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli radio wifi], raise_on_error: false)
            .and_return(command_result(stdout: 'enabled'))
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli -t -f SSID,SIGNAL dev wifi list])
            .and_return(command_result(stdout: nmcli_output))

          result = ubuntu_model.available_network_names
          expect(result).to eq(%w[StrongNet TestNet2 TestNet1 WeakNet])
        end

        it 'does not filter out the connected SSID when the Ubuntu scan includes it' do
          nmcli_output = "CurrentNet:95\nOtherNet:80\nWeakNet:25"
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli radio wifi], raise_on_error: false)
            .and_return(command_result(stdout: 'enabled'))
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli -t -f SSID,SIGNAL dev wifi list])
            .and_return(command_result(stdout: nmcli_output))
          allow(ubuntu_model).to receive(:_connected_network_name).and_return('CurrentNet')

          expect(ubuntu_model.available_network_names).to eq(%w[CurrentNet OtherNet WeakNet])
        end

        it 'does not inject the connected SSID when the Ubuntu scan omits it' do
          nmcli_output = "OtherNet:90\nWeakNet:25"
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli radio wifi], raise_on_error: false)
            .and_return(command_result(stdout: 'enabled'))
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli -t -f SSID,SIGNAL dev wifi list])
            .and_return(command_result(stdout: nmcli_output))
          allow(ubuntu_model).to receive(:_connected_network_name).and_return('CurrentNet')

          expect(ubuntu_model.available_network_names).to eq(%w[OtherNet WeakNet])
        end

        it 'removes duplicate network names' do
          nmcli_output = "TestNet:75\nTestNet:80\nOtherNet:90"
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli radio wifi], raise_on_error: false)
            .and_return(command_result(stdout: 'enabled'))
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli -t -f SSID,SIGNAL dev wifi list])
            .and_return(command_result(stdout: nmcli_output))

          result = ubuntu_model.available_network_names
          expect(result).to eq(%w[OtherNet TestNet])
        end

        it 'filters out empty SSIDs' do
          # NOTE: empty SSIDs show up as lines starting with ':' (colon)
          nmcli_output = "TestNet:75\n:80\nOtherNet:90\n:60"
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli radio wifi], raise_on_error: false)
            .and_return(command_result(stdout: 'enabled'))
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli -t -f SSID,SIGNAL dev wifi list])
            .and_return(command_result(stdout: nmcli_output))

          result = ubuntu_model.available_network_names
          expect(result).to eq(%w[OtherNet TestNet])
        end
      end

      describe '#is_wifi_interface?' do
        it 'returns true for valid wifi interface' do
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[iw dev wlp3s0 info], raise_on_error: false, timeout_in_secs: nil)
            .and_return(command_result(stdout: 'Interface wlp3s0\n\ttype managed', exitstatus: 0))

          expect(ubuntu_model.is_wifi_interface?('wlp3s0')).to be(true)
        end

        it 'returns false for non-wifi interface' do
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[iw dev eth0 info], raise_on_error: false, timeout_in_secs: nil)
            .and_return(command_result(stdout: '', exitstatus: 1))

          expect(ubuntu_model.is_wifi_interface?('eth0')).to be(false)
        end
      end

      describe '#set_nameservers' do
        let(:original_dns_configuration) do
          {
            'ipv4.dns'             => '192.168.1.1 8.8.8.8',
            'ipv4.ignore-auto-dns' => 'yes',
            'ipv6.dns'             => '2606:4700:4700::1111',
            'ipv6.ignore-auto-dns' => 'yes',
          }
        end

        before do
          allow(ubuntu_model).to receive(:dns_configuration_snapshot).and_return(original_dns_configuration)
        end

        it 'successfully sets custom nameservers' do
          nameservers = ['8.8.8.8', '1.1.1.1']
          connection_name = 'MyHomeNetwork'

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)
          allow(ubuntu_model).to receive(:nameservers_from_connection).with(connection_name)
            .and_return(nameservers)

          # Mock the connection-based DNS commands
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', nameservers.join(' ')])
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'yes'])
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .and_return(command_result(stdout: ''))

          result = ubuntu_model.set_nameservers(nameservers)
          expect(result).to eq(nameservers)
        end

        it 'uses the active profile when it differs from the SSID' do
          profile_name = 'Office Profile'
          ssid_name = 'OfficeWiFi'
          nameservers = ['4.4.4.4']

          allow(ubuntu_model).to receive_messages(
            active_connection_profile_name: profile_name,
            _connected_network_name:        ssid_name
          )
          allow(ubuntu_model).to receive(:nameservers_from_connection).with(profile_name)
            .and_return(nameservers)

          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', profile_name, 'ipv4.dns', nameservers.join(' ')])
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', profile_name, 'ipv4.ignore-auto-dns', 'yes'])
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'up', profile_name])
            .and_return(command_result(stdout: ''))

          result = ubuntu_model.set_nameservers(nameservers)
          expect(result).to eq(nameservers)
        end

        it 'accepts and configures IPv6 DNS addresses' do
          ipv6_nameservers = ['2606:4700:4700::1111', '2606:4700:4700::1001']
          connection_name = 'MyHomeNetwork'

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)
          allow(ubuntu_model).to receive(:nameservers_from_connection).with(connection_name)
            .and_return(ipv6_nameservers)

          # Expect IPv6 DNS commands
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns',
              ipv6_nameservers.join(' ')])
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'yes'])
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .and_return(command_result(stdout: ''))

          result = ubuntu_model.set_nameservers(ipv6_nameservers)
          expect(result).to eq(ipv6_nameservers)
        end

        it 'accepts mixed IPv4 and IPv6 DNS addresses' do
          mixed_nameservers = ['8.8.8.8', '2606:4700:4700::1111', '1.1.1.1']
          connection_name = 'MyHomeNetwork'

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)
          allow(ubuntu_model).to receive(:nameservers_from_connection).with(connection_name)
            .and_return(mixed_nameservers)

          # Expect both IPv4 and IPv6 DNS commands
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', '8.8.8.8 1.1.1.1'])
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'yes'])
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns',
              '2606:4700:4700::1111'])
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'yes'])
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .and_return(command_result(stdout: ''))

          result = ubuntu_model.set_nameservers(mixed_nameservers)
          expect(result).to eq(mixed_nameservers)
        end

        it 'replaces a previously dual-stack profile with IPv4-only DNS' do
          connection_name = 'MyHomeNetwork'
          nameservers = ['8.8.8.8', '1.1.1.1']

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)

          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', '8.8.8.8 1.1.1.1'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'yes'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns', ''])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'no'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .ordered.and_return(command_result(stdout: ''))

          result = ubuntu_model.set_nameservers(nameservers)
          expect(result).to eq(nameservers)
        end

        it 'replaces a previously dual-stack profile with IPv6-only DNS' do
          connection_name = 'MyHomeNetwork'
          nameservers = ['2606:4700:4700::1111', '2606:4700:4700::1001']

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)

          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', ''])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'no'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns',
              '2606:4700:4700::1111 2606:4700:4700::1001'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'yes'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .ordered.and_return(command_result(stdout: ''))

          result = ubuntu_model.set_nameservers(nameservers)
          expect(result).to eq(nameservers)
        end

        it 'replaces a previously single-stack profile with the opposite address family' do
          connection_name = 'MyHomeNetwork'
          nameservers = ['2606:4700:4700::1111']

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)

          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', ''])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'no'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns',
              '2606:4700:4700::1111'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'yes'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .ordered.and_return(command_result(stdout: ''))

          result = ubuntu_model.set_nameservers(nameservers)
          expect(result).to eq(nameservers)
        end

        it 'clears both IPv4 and IPv6 nameservers when :clear is specified' do
          connection_name = 'MyHomeNetwork'

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)
          allow(ubuntu_model).to receive(:nameservers_from_connection).with(connection_name).and_return([])

          # Expect both IPv4 and IPv6 clear commands
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', ''])
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'no'])
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns', ''])
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'no'])
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .and_return(command_result(stdout: ''))

          result = ubuntu_model.set_nameservers(:clear)
          expect(result).to eq(:clear)
        end
      end

      describe '#_connected_network_name' do
        it 'returns name of currently connected network' do
          iw_output = "Connected to aa:bb:cc:dd:ee:ff (on wlp3s0)\n\tSSID: MyHomeNetwork\n\tfreq: 2462 MHz"
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[iw dev wlp3s0 link], raise_on_error: false)
            .and_return(command_result(stdout: iw_output))

          expect(ubuntu_model.send(:_connected_network_name)).to eq('MyHomeNetwork')
        end

        it 'returns nil when not connected to any network' do
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[iw dev wlp3s0 link], raise_on_error: false)
            .and_return(command_result(stdout: 'Not connected.'))

          expect(ubuntu_model.send(:_connected_network_name)).to be_nil
        end
      end

      describe '#bssid' do
        it 'returns BSSID for the current wireless association' do
          iw_output = "Connected to aa:bb:cc:dd:ee:ff (on wlp3s0)\n\tSSID: MyHomeNetwork\n\tfreq: 2462 MHz"
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[iw dev wlp3s0 link], raise_on_error: false)
            .and_return(command_result(stdout: iw_output))

          expect(ubuntu_model.bssid).to eq('aa:bb:cc:dd:ee:ff')
        end

        it 'parses BSSID when connected output has leading diagnostics and no interface suffix' do
          iw_output = "\nwarning: stale cached data\nConnected to aa:bb:cc:dd:ee:ff\n\tSSID: MyHomeNetwork"
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[iw dev wlp3s0 link], raise_on_error: false)
            .and_return(command_result(stdout: iw_output))

          expect(ubuntu_model.bssid).to eq('aa:bb:cc:dd:ee:ff')
        end

        it 'returns nil when not associated with a wireless access point' do
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[iw dev wlp3s0 link], raise_on_error: false)
            .and_return(command_result(stdout: 'Not connected.'))

          expect(ubuntu_model.bssid).to be_nil
        end
      end

      describe '#signal_quality' do
        it 'returns the active network signal percentage from nmcli' do
          allow(ubuntu_model).to receive(:connected?).and_return(true)
          allow(ubuntu_model).to receive(:run_command)
            .with(
              ['nmcli', '-t', '-f', 'IN-USE,SIGNAL', 'dev', 'wifi', 'list', '--rescan', 'no'],
              raise_on_error: false
            )
            .and_return(command_result(stdout: " :40\n*:72\n"))

          signal_quality = ubuntu_model.signal_quality

          expect(signal_quality.value).to eq(72)
          expect(signal_quality.unit).to eq(:percent)
          expect(signal_quality.to_s).to eq('72%')
        end

        it 'returns nil when disconnected' do
          allow(ubuntu_model).to receive(:connected?).and_return(false)

          expect(ubuntu_model.signal_quality).to be_nil
        end

        it 'returns nil when nmcli signal lookup fails' do
          allow(ubuntu_model).to receive(:connected?).and_return(true)
          allow(ubuntu_model).to receive(:run_command)
            .and_raise(WifiWand::Error, 'signal unavailable')

          expect(ubuntu_model.signal_quality).to be_nil
        end

        it 'returns nil when active nmcli signal output is blank, missing, or malformed' do
          allow(ubuntu_model).to receive(:connected?).and_return(true)
          allow(ubuntu_model).to receive(:run_command)
            .with(
              ['nmcli', '-t', '-f', 'IN-USE,SIGNAL', 'dev', 'wifi', 'list', '--rescan', 'no'],
              raise_on_error: false
            )
            .and_return(command_result(stdout: "*\n :72\n"))

          expect(ubuntu_model.signal_quality).to be_nil
        end

        it 'returns nil when active nmcli signal output is outside the percentage range' do
          allow(ubuntu_model).to receive(:connected?).and_return(true)
          allow(ubuntu_model).to receive(:run_command)
            .with(
              ['nmcli', '-t', '-f', 'IN-USE,SIGNAL', 'dev', 'wifi', 'list', '--rescan', 'no'],
              raise_on_error: false
            )
            .and_return(command_result(stdout: "*:101\n"))

          expect(ubuntu_model.signal_quality).to be_nil
        end
      end

      describe '#active_connection_profile_name' do
        it 'parses the active profile from nmcli dev show output' do
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          nmcli_output = "GENERAL.CONNECTION:Office Profile\nGENERAL.DEVICE:wlp3s0"
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '-t', '-f', 'GENERAL.CONNECTION', 'dev', 'show', 'wlp3s0'], raise_on_error: false)
            .and_return(command_result(stdout: nmcli_output))

          expect(ubuntu_model.active_connection_profile_name).to eq('Office Profile')
        end

        it 'unescapes literal colons in the active profile name' do
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          nmcli_output = "GENERAL.CONNECTION:Cafe\\:Guest\nGENERAL.DEVICE:wlp3s0"
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '-t', '-f', 'GENERAL.CONNECTION', 'dev', 'show', 'wlp3s0'], raise_on_error: false)
            .and_return(command_result(stdout: nmcli_output))

          expect(ubuntu_model.active_connection_profile_name).to eq('Cafe:Guest')
        end

        it 'returns nil for NetworkManager no-connection placeholder output' do
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          nmcli_output = "GENERAL.CONNECTION:--\nGENERAL.DEVICE:wlp3s0"
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '-t', '-f', 'GENERAL.CONNECTION', 'dev', 'show', 'wlp3s0'], raise_on_error: false)
            .and_return(command_result(stdout: nmcli_output))

          expect(ubuntu_model.active_connection_profile_name).to be_nil
        end

        it 'returns nil when wifi interface cannot be determined' do
          allow(ubuntu_model).to receive(:wifi_interface).and_return(nil)
          expect(ubuntu_model.active_connection_profile_name).to be_nil
        end

        it 'returns nil when nmcli lookup fails' do
          allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '-t', '-f', 'GENERAL.CONNECTION', 'dev', 'show', 'wlp3s0'], raise_on_error: false)
            .and_raise(os_command_error(exitstatus: 10, command: 'nmcli', text: 'failed'))

          expect(ubuntu_model.active_connection_profile_name).to be_nil
        end
      end

      describe '#connection_ready?' do
        it 'returns true for an active matching connection even without an IPv4 address' do
          allow(ubuntu_model).to receive_messages(
            _connected_network_name:        'NetA',
            active_connection_profile_name: 'NetA',
            connected?:                     true,
            _ipv4_addresses:                []
          )

          expect(ubuntu_model.connection_ready?('NetA')).to be(true)
        end

        it 'returns false when the active profile is missing' do
          allow(ubuntu_model).to receive_messages(
            _connected_network_name:        'NetA',
            active_connection_profile_name: nil,
            connected?:                     true
          )

          expect(ubuntu_model.connection_ready?('NetA')).to be(false)
        end
      end

      describe 'private helper methods' do
        describe '#get_security_parameter' do
          it 'detects WPA2 security and returns correct parameter' do
            wifi_list_output = 'MyNetwork:WPA2'
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], raise_on_error: false)
              .and_return(command_result(stdout: wifi_list_output))

            result = ubuntu_model.send(:get_security_parameter, 'MyNetwork')
            expect(result).to eq('802-11-wireless-security.psk')
          end

          it 'detects WEP security and returns correct parameter' do
            wifi_list_output = 'MyNetwork:WEP'
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], raise_on_error: false)
              .and_return(command_result(stdout: wifi_list_output))

            result = ubuntu_model.send(:get_security_parameter, 'MyNetwork')
            expect(result).to eq('802-11-wireless-security.wep-key0')
          end

          it 'returns nil when network not found in scan' do
            wifi_list_output = 'OtherNetwork:WPA2'
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], raise_on_error: false)
              .and_return(command_result(stdout: wifi_list_output))

            expect(ubuntu_model.send(:get_security_parameter, 'NonExistent')).to be_nil
          end
        end

        describe '#find_best_profile_for_ssid' do
          it 'finds existing connection profile for SSID' do
            connection_output = "MyNetwork:802-11-wireless:1672574400\n" \
              "Renamed MyNetwork:802-11-wireless:1672660200\n" \
              'OtherNetwork:802-11-wireless:1672547800'
            allow(ubuntu_model).to receive(:run_command)
              .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
              .and_return(command_result(stdout: connection_output))
            stub_saved_profile_ssid('MyNetwork', 'MyNetwork')
            stub_saved_profile_ssid('Renamed MyNetwork', 'MyNetwork')
            stub_saved_profile_ssid('OtherNetwork', 'OtherNetwork')

            result = ubuntu_model.send(:find_best_profile_for_ssid, 'MyNetwork')
            expect(result).to eq('Renamed MyNetwork')  # Most recent matching profile
          end

          it 'returns nil when no profile exists for SSID' do
            connection_output =
              "MyNetwork:802-11-wireless:1672574400\n" \
                'OtherNetwork:802-11-wireless:1672547800'
            allow(ubuntu_model).to receive(:run_command)
              .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
              .and_return(command_result(stdout: connection_output))
            stub_saved_profile_ssid('MyNetwork', 'MyNetwork')
            stub_saved_profile_ssid('OtherNetwork', 'OtherNetwork')

            expect(ubuntu_model.send(:find_best_profile_for_ssid, 'NonExistent')).to be_nil
          end
        end

        describe '#_preferred_network_password' do
          it 'retrieves stored PSK password for connection profile' do
            password_output = '802-11-wireless-security.psk:    my-secret-password'
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli --show-secrets connection show MyProfile], raise_on_error: false)
              .and_return(command_result(stdout: password_output))

            result = ubuntu_model.send(:_preferred_network_password, 'MyProfile')
            expect(result).to eq('my-secret-password')
          end

          it 'uses unbounded command execution by default' do
            password_output = '802-11-wireless-security.psk:    my-secret-password'
            expect(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli --show-secrets connection show MyProfile], raise_on_error: false)
              .and_return(command_result(stdout: password_output))

            result = ubuntu_model.send(:_preferred_network_password, 'MyProfile')
            expect(result).to eq('my-secret-password')
          end

          it 'passes a requested timeout to the secrets command' do
            password_output = '802-11-wireless-security.psk:    my-secret-password'
            expect(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli --show-secrets connection show MyProfile], raise_on_error: false,
                timeout_in_secs: 0.25)
              .and_return(command_result(stdout: password_output))

            result = ubuntu_model.send(:_preferred_network_password, 'MyProfile', timeout_in_secs: 0.25)
            expect(result).to eq('my-secret-password')
          end

          it 'retrieves stored WEP password for connection profile' do
            password_output = '802-11-wireless-security.wep-key0:    legacy-wep-key'
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli --show-secrets connection show MyProfile], raise_on_error: false)
              .and_return(command_result(stdout: password_output))

            result = ubuntu_model.send(:_preferred_network_password, 'MyProfile')
            expect(result).to eq('legacy-wep-key')
          end

          it 'prefers a real PSK over a placeholder WEP value when both are present' do
            password_output = <<~OUTPUT
              802-11-wireless-security.wep-key0:      --
              802-11-wireless-security.psk:           weplaychess
            OUTPUT
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli --show-secrets connection show MyProfile], raise_on_error: false)
              .and_return(command_result(stdout: password_output))

            result = ubuntu_model.send(:_preferred_network_password, 'MyProfile')
            expect(result).to eq('weplaychess')
          end

          it 'returns nil when no password is stored' do
            password_output = <<~OUTPUT
              connection.id: MyProfile
              802-11-wireless-security.key-mgmt: none
            OUTPUT
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli --show-secrets connection show MyProfile], raise_on_error: false)
              .and_return(command_result(stdout: password_output))

            expect(ubuntu_model.send(:_preferred_network_password, 'MyProfile')).to be_nil
          end
        end

        describe '#extract_preferred_network_secret' do
          it 'ignores placeholder and empty values before falling back to a real WEP secret' do
            connection_output = <<~OUTPUT
              802-11-wireless-security.psk:
              802-11-wireless-security.wep-key0:      actual-wep-key
            OUTPUT

            result = ubuntu_model.extract_preferred_network_secret(connection_output)
            expect(result).to eq('actual-wep-key')
          end

          it 'returns nil when only placeholder secret values are present' do
            connection_output = <<~OUTPUT
              802-11-wireless-security.wep-key0:      --
            OUTPUT

            result = ubuntu_model.extract_preferred_network_secret(connection_output)
            expect(result).to be_nil
          end
        end
      end

      # Regression tests: nmcli terse output escaping in SSIDs/profiles.
      describe 'nmcli terse parsing' do
        describe '#nmcli_split' do
          it 'unescapes literal colons without treating them as field separators' do
            expect(ubuntu_model.nmcli_split('Cafe\:Guest:75', 2)).to eq(['Cafe:Guest', '75'])
          end

          it 'unescapes literal backslashes in field values' do
            expect(ubuntu_model.nmcli_split('Lab\\\\Net:82', 2)).to eq(['Lab\\Net', '82'])
          end

          it 'splits on a field separator after an escaped literal backslash' do
            expect(ubuntu_model.nmcli_split('EndsWithSlash\\\\:55', 2)).to eq(['EndsWithSlash\\', '55'])
          end

          it 'preserves unknown escape sequences literally' do
            expect(ubuntu_model.nmcli_split('Unknown\\xEscape:55', 2)).to eq(['Unknown\\xEscape', '55'])
          end
        end

        describe '#_available_network_names with colon-containing SSIDs' do
          it 'correctly parses an SSID that contains a literal colon' do
            # nmcli escapes the colon in "Cafe:Guest" as "Cafe\\:Guest"
            nmcli_output = "Cafe\\:Guest:75\nRegularNet:90"
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli radio wifi], raise_on_error: false)
              .and_return(command_result(stdout: 'enabled'))
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli -t -f SSID,SIGNAL dev wifi list])
              .and_return(command_result(stdout: nmcli_output))

            result = ubuntu_model.available_network_names
            expect(result).to include('Cafe:Guest', 'RegularNet')
          end
        end

        describe '#_available_network_names with backslash-containing SSIDs' do
          it 'correctly parses an SSID that contains a literal backslash' do
            nmcli_output = "Lab\\\\Net:75\nRegularNet:90"
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli radio wifi], raise_on_error: false)
              .and_return(command_result(stdout: 'enabled'))
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli -t -f SSID,SIGNAL dev wifi list])
              .and_return(command_result(stdout: nmcli_output))

            result = ubuntu_model.available_network_names
            expect(result).to include('Lab\\Net', 'RegularNet')
          end
        end

        describe '#_connected_network_name with colon-containing SSID' do
          it 'returns the full SSID including its embedded colon' do
            iw_output = "Connected to aa:bb:cc:dd:ee:ff (on wlp3s0)\n\tSSID: Corp:Wifi\n\tfreq: 5180 MHz"
            allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[iw dev wlp3s0 link], raise_on_error: false)
              .and_return(command_result(stdout: iw_output))

            expect(ubuntu_model.send(:_connected_network_name)).to eq('Corp:Wifi')
          end
        end

        describe '#get_security_parameter with colon-containing SSID' do
          it 'matches the exact SSID and returns the correct security parameter' do
            # "Corp:Wifi" is escaped as "Corp\:Wifi" in nmcli terse output
            nmcli_output = "Corp\\:Wifi:WPA2\nCorpNet:WPA2"
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], raise_on_error: false)
              .and_return(command_result(stdout: nmcli_output))

            expect(
              ubuntu_model.send(:get_security_parameter, 'Corp:Wifi')
            ).to eq('802-11-wireless-security.psk')
          end

          it 'does not match a prefix-collision SSID (Office vs Office-Guest)' do
            nmcli_output = "Office-Guest:WPA2\nOtherNet:WPA2"
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli -t -f SSID,SECURITY dev wifi list], raise_on_error: false)
              .and_return(command_result(stdout: nmcli_output))

            expect(ubuntu_model.send(:get_security_parameter, 'Office')).to be_nil
          end
        end

        describe '#find_best_profile_for_ssid with colon-containing profile name' do
          it 'correctly parses profile names and SSIDs that contain literal colons' do
            connection_output =
              "Corp\\:Profile:802-11-wireless:1672660200\n" \
                'OtherNetwork:802-11-wireless:1672574400'
            allow(ubuntu_model).to receive(:run_command)
              .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
              .and_return(command_result(stdout: connection_output))
            stub_saved_profile_ssid('Corp:Profile', 'Corp\\:Net')
            stub_saved_profile_ssid('OtherNetwork', 'OtherNetwork')

            expect(ubuntu_model.send(:find_best_profile_for_ssid, 'Corp:Net')).to eq('Corp:Profile')
          end

          it 'matches configured SSIDs when the profile and SSID contain literal backslashes' do
            connection_output =
              "Lab\\\\Profile:802-11-wireless:1672660200\n" \
                'OtherNetwork:802-11-wireless:1672574400'
            allow(ubuntu_model).to receive(:run_command)
              .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
              .and_return(command_result(stdout: connection_output))
            stub_saved_profile_ssid('Lab\\Profile', 'Lab\\\\Net')
            stub_saved_profile_ssid('OtherNetwork', 'OtherNetwork')

            expect(ubuntu_model.send(:find_best_profile_for_ssid, 'Lab\\Net')).to eq('Lab\\Profile')
          end

          it 'does not match a profile whose name merely starts with the SSID' do
            connection_output =
              "Office-Guest:802-11-wireless:1672660200\n" \
                'Office Extra:802-11-wireless:1672574400'
            allow(ubuntu_model).to receive(:run_command)
              .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
              .and_return(command_result(stdout: connection_output))
            stub_saved_profile_ssid('Office-Guest', 'Office-Guest')
            stub_saved_profile_ssid('Office Extra', 'Office Extra')

            expect(ubuntu_model.send(:find_best_profile_for_ssid, 'Office')).to be_nil
          end

          it 'matches the newest NM duplicate profile by configured SSID' do
            connection_output = "Office:802-11-wireless:1672574400\n" \
              "Office 1:802-11-wireless:1672660200\n" \
              'Office-Guest:802-11-wireless:1672547800'
            allow(ubuntu_model).to receive(:run_command)
              .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
              .and_return(command_result(stdout: connection_output))
            stub_saved_profile_ssid('Office', 'Office')
            stub_saved_profile_ssid('Office 1', 'Office')
            stub_saved_profile_ssid('Office-Guest', 'Office-Guest')

            result = ubuntu_model.send(:find_best_profile_for_ssid, 'Office')
            expect(result).to eq('Office 1')
          end
        end

        describe '#preferred_network_password with backslash-containing values' do
          it 'uses the saved password from the matching backslash-containing profile and SSID' do
            connection_output =
              "Lab\\\\Profile:802-11-wireless:1672660200\n" \
                'OtherNetwork:802-11-wireless:1672574400'
            allow(ubuntu_model).to receive(:run_command)
              .with(nmcli_saved_profile_summary_fields, raise_on_error: false)
              .and_return(command_result(stdout: connection_output))
            stub_saved_profile_ssid('Lab\\Profile', 'Lab\\\\Net')
            stub_saved_profile_ssid('OtherNetwork', 'OtherNetwork')
            expect(ubuntu_model).to receive(:run_command)
              .with(['nmcli', '--show-secrets', 'connection', 'show',
                'Lab\\Profile'], raise_on_error: false)
              .and_return(command_result(stdout: '802-11-wireless-security.psk:    saved-secret'))

            expect(ubuntu_model.preferred_network_password('Lab\\Net')).to eq('saved-secret')
          end
        end

        describe '#nameservers with colon-containing active profile name' do
          it 'uses the unescaped profile name for connection lookup' do
            allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
            expect(ubuntu_model).to receive(:run_command)
              .with(['nmcli', '-t', '-f', 'GENERAL.CONNECTION', 'dev', 'show',
                'wlp3s0'], raise_on_error: false)
              .and_return(command_result(stdout: 'GENERAL.CONNECTION:Cafe\\:Guest'))
            expect(ubuntu_model).to receive(:nameservers_from_connection).with('Cafe:Guest')
              .and_return(['1.1.1.1'])

            expect(ubuntu_model.nameservers).to eq(['1.1.1.1'])
          end
        end

        describe '#set_nameservers with colon-containing active profile name' do
          it 'passes the unescaped profile name back to nmcli' do
            allow(ubuntu_model).to receive(:wifi_interface).and_return('wlp3s0')
            expect(ubuntu_model).to receive(:run_command)
              .with(['nmcli', '-t', '-f', 'GENERAL.CONNECTION', 'dev', 'show',
                'wlp3s0'], raise_on_error: false)
              .and_return(command_result(stdout: 'GENERAL.CONNECTION:Cafe\\:Guest'))
            expect(ubuntu_model).to receive(:run_command)
              .with(['nmcli', 'connection', 'modify', 'Cafe:Guest', 'ipv4.dns', '1.1.1.1'])
              .ordered.and_return(command_result(stdout: ''))
            expect(ubuntu_model).to receive(:run_command)
              .with(['nmcli', 'connection', 'modify', 'Cafe:Guest', 'ipv4.ignore-auto-dns', 'yes'])
              .ordered.and_return(command_result(stdout: ''))
            expect(ubuntu_model).to receive(:run_command)
              .with(['nmcli', 'connection', 'modify', 'Cafe:Guest', 'ipv6.dns', ''])
              .ordered.and_return(command_result(stdout: ''))
            expect(ubuntu_model).to receive(:run_command)
              .with(['nmcli', 'connection', 'modify', 'Cafe:Guest', 'ipv6.ignore-auto-dns', 'no'])
              .ordered.and_return(command_result(stdout: ''))
            expect(ubuntu_model).to receive(:run_command)
              .with(['nmcli', 'connection', 'up', 'Cafe:Guest'])
              .ordered.and_return(command_result(stdout: ''))

            expect(ubuntu_model.set_nameservers(['1.1.1.1'])).to eq(['1.1.1.1'])
          end
        end

        describe '#connection_security_type with colon-containing SSID' do
          it 'returns the correct security type for an SSID with a colon' do
            allow(ubuntu_model).to receive(:_connected_network_name).and_return('Corp:Wifi')
            nmcli_output = "*:Corp\\:Wifi:WPA2\n:CorpNet:WPA2"
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli -t -f IN-USE,SSID,SECURITY dev wifi list], raise_on_error: false)
              .and_return(command_result(stdout: nmcli_output))

            expect(ubuntu_model.connection_security_type).to eq('WPA2')
          end

          it 'does not misidentify a prefix-collision SSID (Office vs Office-Guest)' do
            allow(ubuntu_model).to receive(:_connected_network_name).and_return('Office')
            nmcli_output = '*:Office-Guest:WPA2'
            allow(ubuntu_model).to receive(:run_command)
              .with(%w[nmcli -t -f IN-USE,SSID,SECURITY dev wifi list], raise_on_error: false)
              .and_return(command_result(stdout: nmcli_output))

            expect(ubuntu_model.connection_security_type).to be_nil
          end
        end
      end
    end

    context 'when running error handling tests' do
      describe '#wifi_on' do
        it 'raises WifiEnableError when command succeeds but wifi remains off' do
          # Mock specific command calls to avoid real system calls
          allow(ubuntu_model).to receive(:run_command).with(/nmcli radio wifi on/, anything)
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command).with(/nmcli radio wifi$/, anything)
            .and_return(command_result(stdout: 'disabled'))

          # Mock till to raise WaitTimeoutError; wifi_on converts it to WifiEnableError.
          allow(ubuntu_model).to receive(:till).and_raise(wait_timeout_error(action: :wifi_on, timeout: 5))

          expect { ubuntu_model.wifi_on }.to raise_error(WifiWand::WifiEnableError)
        end
      end

      describe '#wifi_off' do
        it 'raises WifiDisableError when command succeeds but wifi remains on' do
          # Mock specific command calls to avoid real system calls
          allow(ubuntu_model).to receive(:run_command).with(%w[nmcli radio wifi off], anything)
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command).with(%w[nmcli radio wifi], anything)
            .and_return(command_result(stdout: 'enabled'))

          # Mock till to raise WaitTimeoutError; wifi_off converts it to WifiDisableError.
          allow(ubuntu_model).to receive(:till).and_raise(wait_timeout_error(action: :wifi_off, timeout: 5))

          expect { ubuntu_model.wifi_off }.to raise_error(WifiWand::WifiDisableError)
        end
      end

      describe '#disconnect' do
        it 'reports nmcli disconnect failures as disconnection errors' do
          allow(ubuntu_model).to receive_messages(wifi_on?: true, wifi_interface: 'wlan0')
          allow(ubuntu_model).to receive(:connected_network_name).and_return('CafeWiFi')
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli dev disconnect wlan0])
            .and_raise(
              os_command_error(
                exitstatus: 1,
                command:    'nmcli dev disconnect wlan0',
                text:       'Device disconnect failed'
              )
            )

          expect { ubuntu_model.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
            expect(error.network_name).to eq('CafeWiFi')
            expect(error.reason).to include('Device disconnect failed')
            expect(error.reason).to include('Command failed: nmcli dev disconnect wlan0')
          end
        end

        it 'reports verification probe failures as disconnection errors' do
          allow(ubuntu_model).to receive_messages(wifi_on?: true, wifi_interface: 'wlan0')
          allow(ubuntu_model).to receive(:connected_network_name).and_return('CafeWiFi', nil)
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli dev disconnect wlan0])
            .and_return(command_result(stdout: ''))
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '-t', '-f', 'DEVICE', 'connection', 'show', '--active'], raise_on_error: false)
            .and_return(command_result(
              stdout:     'NetworkManager unavailable',
              exitstatus: 1,
              command:    'nmcli -t -f DEVICE connection show --active'
            ))

          expect { ubuntu_model.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
            expect(error.network_name).to eq('CafeWiFi')
            expect(error.reason).to include('NetworkManager unavailable')
            expect(error.reason).to include('nmcli -t -f DEVICE connection show --active')
          end
        end

        it 'reports nmcli disconnect timeouts as disconnection errors' do
          allow(ubuntu_model).to receive_messages(
            wifi_on?:               true,
            connected_network_name: 'CafeWiFi',
            wifi_interface:         'wlan0'
          )
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli dev disconnect wlan0])
            .and_raise(WifiWand::CommandTimeoutError.new(
              command:         'nmcli dev disconnect wlan0',
              timeout_in_secs: 5
            ))

          expect { ubuntu_model.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
            expect(error.network_name).to eq('CafeWiFi')
            expect(error.reason).to include('Command timed out after 5 seconds')
            expect(error.reason).to include('nmcli dev disconnect wlan0')
          end
        end

        it 'is a no-op when already disconnected' do
          allow(ubuntu_model).to receive_messages(
            wifi_on?:               true,
            connected_network_name: nil,
            connected?:             false
          )
          allow(ubuntu_model).to receive(:disconnect_associated?).and_return(false)
          allow(ubuntu_model).to receive(:wait_until_disassociated!)
          allow(ubuntu_model).to receive(:run_command)

          expect(ubuntu_model.disconnect).to be_nil
          expect(ubuntu_model).not_to have_received(:run_command)
          expect(ubuntu_model).not_to have_received(:wait_until_disassociated!)
        end
      end

      describe '#set_nameservers' do
        let(:original_dns_configuration) do
          {
            'ipv4.dns'             => '192.168.1.1 8.8.8.8',
            'ipv4.ignore-auto-dns' => 'yes',
            'ipv6.dns'             => '2606:4700:4700::1111',
            'ipv6.ignore-auto-dns' => 'yes',
          }
        end

        before do
          allow(ubuntu_model).to receive(:dns_configuration_snapshot).and_return(original_dns_configuration)
        end

        it 'raises error for invalid IP addresses before reading connection state' do
          invalid_nameservers = ['invalid.ip', '256.256.256.256']
          connection_name = 'MyHomeNetwork'

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)
          expect(ubuntu_model).not_to receive(:dns_configuration_snapshot)

          expect do
            silence_output do
              ubuntu_model.set_nameservers(invalid_nameservers)
            end
          end.to raise_error(WifiWand::InvalidIPAddressError)
        end

        it 'raises error for invalid IPv6 addresses before reading connection state' do
          invalid_nameservers = ['2606:4700:4700::1111', '2001:db8:::1']
          connection_name = 'MyHomeNetwork'

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)
          expect(ubuntu_model).not_to receive(:dns_configuration_snapshot)

          expect { ubuntu_model.set_nameservers(invalid_nameservers) }
            .to raise_error(WifiWand::InvalidIPAddressError) do |error|
              expect(error.invalid_addresses).to eq(['2001:db8:::1'])
            end
        end

        it 'raises error for nil nameserver input before reading connection state' do
          invalid_nameservers = ['8.8.8.8', nil]
          connection_name = 'MyHomeNetwork'

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)
          expect(ubuntu_model).not_to receive(:dns_configuration_snapshot)

          expect { ubuntu_model.set_nameservers(invalid_nameservers) }
            .to raise_error(WifiWand::InvalidIPAddressError) do |error|
              expect(error.invalid_addresses).to eq([nil])
            end
        end

        it 'raises error for non-string nameserver input before reading connection state' do
          invalid_nameservers = ['8.8.8.8', 123]
          connection_name = 'MyHomeNetwork'

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)
          expect(ubuntu_model).not_to receive(:dns_configuration_snapshot)

          expect { ubuntu_model.set_nameservers(invalid_nameservers) }
            .to raise_error(WifiWand::InvalidIPAddressError) do |error|
              expect(error.invalid_addresses).to eq([123])
            end
        end

        it 'rolls back prior DNS mutations when a later modify command fails' do
          connection_name = 'MyHomeNetwork'

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', '8.8.8.8'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'yes'])
            .ordered.and_raise(
              os_command_error(
                exitstatus: 1,
                command:    'nmcli connection modify',
                text:       'Connection modify failed'
              )
            )
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', '192.168.1.1 8.8.8.8'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'yes'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns', '2606:4700:4700::1111'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'yes'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .ordered.and_return(command_result(stdout: ''))

          expect { ubuntu_model.set_nameservers(['8.8.8.8']) }
            .to raise_error(WifiWand::DnsConfigurationError, /modifying the connection profile/)
        end

        it 'raises a DNS configuration error when clearing DNS fails' do
          connection_name = 'MyHomeNetwork'

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', ''])
            .and_raise(
              os_command_error(
                exitstatus: 1,
                command:    'nmcli connection modify',
                text:       'Permission denied'
              )
            )

          expect { ubuntu_model.set_nameservers(:clear) }
            .to raise_error(WifiWand::DnsConfigurationError, /Permission denied/)
        end

        it 'raises a DNS configuration error when reading the current DNS state fails' do
          connection_name = 'MyHomeNetwork'

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)
          allow(ubuntu_model).to receive(:dns_configuration_snapshot).and_raise(
            os_command_error(
              exitstatus: 1,
              command:    'nmcli --get-values ipv4.dns',
              text:       'Failed to read current DNS state'
            )
          )

          expect { ubuntu_model.set_nameservers(['8.8.8.8']) }
            .to raise_error(WifiWand::DnsConfigurationError, /Failed to read current DNS state/)
        end

        it 'rolls back DNS settings when connection activation fails after modification' do
          connection_name = 'MyHomeNetwork'
          nameservers = ['8.8.8.8']

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', '8.8.8.8'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'yes'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns', ''])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'no'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .ordered.and_raise(
              os_command_error(
                exitstatus: 1,
                command:    'nmcli connection up',
                text:       'Activation failed'
              )
            )
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', '192.168.1.1 8.8.8.8'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'yes'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns', '2606:4700:4700::1111'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'yes'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .ordered.and_return(command_result(stdout: ''))

          expect { ubuntu_model.set_nameservers(nameservers) }
            .to raise_error(WifiWand::DnsConfigurationError, /reactivating the connection/)
        end

        it 'surfaces rollback failure when restoration does not complete' do
          connection_name = 'MyHomeNetwork'

          allow(ubuntu_model).to receive(:active_connection_profile_name).and_return(connection_name)
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', '8.8.8.8'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.ignore-auto-dns', 'yes'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.dns', ''])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv6.ignore-auto-dns', 'no'])
            .ordered.and_return(command_result(stdout: ''))
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'up', connection_name])
            .ordered.and_raise(
              os_command_error(
                exitstatus: 1,
                command:    'nmcli connection up',
                text:       'Activation failed'
              )
            )
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'modify', connection_name, 'ipv4.dns', '192.168.1.1 8.8.8.8'])
            .ordered.and_raise(
              os_command_error(
                exitstatus: 1,
                command:    'nmcli connection modify',
                text:       'Rollback modify failed'
              )
            )

          expect { ubuntu_model.set_nameservers(['8.8.8.8']) }
            .to raise_error(WifiWand::DnsConfigurationError, /rollback failed: Rollback modify failed/)
        end

        it 'handles cases when no active connection exists' do
          allow(ubuntu_model).to receive_messages(
            active_connection_profile_name: nil,
            _connected_network_name:        nil
          )

          expect { ubuntu_model.set_nameservers(['8.8.8.8']) }
            .to raise_error(WifiWand::WifiInterfaceError, /No active Wi-Fi connection/)
        end

        it 'raises the no-active-connection error for the NetworkManager placeholder profile' do
          allow(ubuntu_model).to receive_messages(
            wifi_interface:          'wlp3s0',
            _connected_network_name: nil
          )
          allow(ubuntu_model).to receive(:run_command)
            .with(['nmcli', '-t', '-f', 'GENERAL.CONNECTION', 'dev', 'show',
              'wlp3s0'], raise_on_error: false)
            .and_return(command_result(stdout: 'GENERAL.CONNECTION:--'))

          expect(ubuntu_model).not_to receive(:dns_configuration_snapshot)
          expect { ubuntu_model.set_nameservers(['8.8.8.8']) }
            .to raise_error(WifiWand::WifiInterfaceError, /No active Wi-Fi connection/)
        end
      end

      describe '#available_network_names' do
        it 'handles nmcli scan failures' do
          # Mock wifi_on? to return true so available_network_names calls _available_network_names
          allow(ubuntu_model).to receive(:wifi_on?).and_return(true)
          # Mock the specific command to fail
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli -t -f SSID,SIGNAL dev wifi list])
            .and_raise(os_command_error(
              exitstatus: 1,
              command:    'nmcli -t -f SSID,SIGNAL dev wifi list',
              text:       'Scan failed'
            ))

          expect { ubuntu_model.available_network_names }
            .to raise_error(WifiWand::CommandExecutor::OsCommandError, /Scan failed/)
        end
      end

      describe '#is_wifi_interface?' do
        it 'handles iw dev info command failures' do
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[iw dev wlan0 info], raise_on_error: false, timeout_in_secs: nil)
            .and_return(command_result(stdout: '', stderr: 'No such device', exitstatus: 1))

          expect(ubuntu_model.is_wifi_interface?('wlan0')).to be(false)
        end
      end

      describe '#_connect error scenarios' do
        it 'raises NetworkNotFoundError for non-existent network' do
          # Mock nmcli to simulate network not found scenario without real commands
          allow(ubuntu_model).to receive_messages(
            _connected_network_name:    nil,
            find_best_profile_for_ssid: nil
          )
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli dev wifi connect non_existent_network_123])
            .and_raise(
              os_command_error(
                exitstatus: 10,
                command:    'nmcli dev wifi connect',
                text:       'No network with SSID "non_existent_network_123" found'
              )
            )

          expect do
            ubuntu_model._connect('non_existent_network_123')
          end.to raise_error(WifiWand::NetworkNotFoundError)
        end

        it 'raises NetworkConnectionError for generic connection activation failures' do
          # Mock various paths that _connect might take without real commands
          # Mock connection check
          # Mock profile finding
          allow(ubuntu_model).to receive_messages(
            _connected_network_name:    nil,
            find_best_profile_for_ssid: nil
          )
          # Mock the actual connection attempt that will be made
          allow(ubuntu_model).to receive(:run_command)
            .with(%w[nmcli dev wifi connect TestNetwork password test_password])
            .and_raise(
              os_command_error(
                exitstatus: 4,
                command:    'nmcli dev wifi connect',
                text:       'Connection activation failed'
              )
            )

          # Generic activation failed should now raise NetworkConnectionError (out of range)
          expect { ubuntu_model._connect('TestNetwork', 'test_password') }
            .to raise_error(WifiWand::NetworkConnectionError, /out of range/)
        end

        it 'handles security parameter detection failures gracefully' do
          # Mock get_security_parameter to return nil (detection failure)
          # Mock the fallback connection attempt to avoid real network connection
          allow(ubuntu_model).to receive_messages(
            get_security_parameter:     command_result(stdout: nil),
            _connected_network_name:    nil,
            find_best_profile_for_ssid: nil
          )
          allow(ubuntu_model).to receive(:run_command)
            .with(/nmcli dev wifi connect.*password/)
            .and_return(command_result(stdout: ''))  # Simulate successful connection

          # Should fall back to direct connection attempt without actually connecting
          expect { ubuntu_model._connect('TestNetwork', 'test_password') }
            .not_to raise_error
        end
      end
    end

    # System-modifying tests (will change wifi state)
    context 'when running system-modifying operations',
      :real_env_read_write, real_env_os: :os_ubuntu do
      describe '#wifi_on' do
        it 'turns wifi on when it is off' do
          ubuntu_model.wifi_off
          expect(ubuntu_model.wifi_on?).to be(false)

          ubuntu_model.wifi_on
          expect(ubuntu_model.wifi_on?).to be(true)
        end
      end

      describe '#wifi_off' do
        it 'turns wifi off when it is on' do
          ubuntu_model.wifi_on
          expect(ubuntu_model.wifi_on?).to be(true)

          ubuntu_model.wifi_off
          expect(ubuntu_model.wifi_on?).to be(false)
        end
      end

      describe '#disconnect' do
        it 'disconnects from current network' do
          # Can disconnect even when not connected to a network
          expect { ubuntu_model.disconnect }.not_to raise_error
        end
      end

      describe '#remove_preferred_network' do
        it 'removes a preferred network' do
          connection_name = 'SavedProfile'

          allow(ubuntu_model).to receive(:saved_wifi_profiles)
            .and_return([saved_wifi_profile(connection_name, ssid: connection_name)])
          expect(ubuntu_model).to receive(:run_command)
            .with(['nmcli', 'connection', 'delete', connection_name])
            .and_return(command_result(stdout: ''))

          expect { ubuntu_model.remove_preferred_network(connection_name) }.not_to raise_error
        end

        it 'handles removal of non-existent network' do
          allow(ubuntu_model).to receive(:saved_wifi_profiles).and_return([])

          expect { ubuntu_model.remove_preferred_network('non_existent_network_123') }.not_to raise_error
        end
      end

      describe '#set_nameservers' do
        let(:valid_nameservers) { ['8.8.8.8', '8.8.4.4'] }

        it 'sets valid nameservers' do
          ubuntu_model.wifi_on

          result = ubuntu_model.set_nameservers(valid_nameservers)
          expect(result).to eq(valid_nameservers)

          # Poll until the new nameservers appear in the active connection profile
          wait_for(timeout: 30, interval: 0.5, description: 'nameservers to be applied') do
            (valid_nameservers - ubuntu_model.nameservers).empty?
          end

          expect(ubuntu_model.nameservers).to include(*valid_nameservers)
        end
      end
    end

    context 'when running read-only real-environment checks',
      :real_env_read_only, real_env_os: :os_ubuntu do
      describe 'interface detection' do
        it 'detects WiFi interface correctly' do
          interface = ubuntu_model.probe_wifi_interface
          expect(interface).to match(wifi_interface_regex) if interface
        end

        it 'validates detected interface is actually WiFi' do
          interface = ubuntu_model.wifi_interface
          expect(ubuntu_model.is_wifi_interface?(interface)).to be(true) if interface
        end
      end

      describe 'network information' do
        it 'retrieves IPv4 addresses' do
          expect(ubuntu_model.ipv4_addresses).to be_a_non_empty_array_of_ip_addresses
        end

        it 'retrieves MAC address' do
          expect(ubuntu_model.mac_address).to match(/^([0-9a-f]{2}:){5}[0-9a-f]{2}$/i)
        end

        it 'retrieves nameservers' do
          expect(ubuntu_model.nameservers).to be_an(Array)
        end

        it 'returns a string or nil for connected network name' do
          skip 'WiFi is currently off' unless ubuntu_model.wifi_on?
          expect(ubuntu_model.connected_network_name).to be_nil_or_a_string
        end
      end

      describe 'network scanning' do
        it 'can scan for available networks when WiFi is already on' do
          skip 'WiFi is currently off' unless ubuntu_model.wifi_on?

          networks = ubuntu_model.available_network_names
          expect(networks).to be_an(Array)
        end
      end
    end
  end
end
