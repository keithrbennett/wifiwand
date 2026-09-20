# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/platforms/mac/helper/bundle'
require_relative '../../../../lib/wifi_wand/platforms/mac/network_identity_reader'

module WifiWand
  describe Platforms::Mac::NetworkIdentityReader do
    subject(:reader) do
      described_class.new(
        helper_client_provider:                 -> { helper_client },
        command_runner:                         command_runner,
        system_profiler_wifi_data_reader:       ->(timeout_in_secs: nil) {
          system_profiler_wifi_data_reader.call(timeout_in_secs)
        },
        system_profiler_wifi_data_cache_runner: ->(&block) { block.call },
        wifi_power_reader:                      -> { wifi_on },
        wifi_interface_provider:                -> { wifi_interface },
        default_interface_provider:             -> { default_interface },
        ipv4_addresses_reader:                  -> { ipv4_addresses },
        ipv6_addresses_reader:                  -> { ipv6_addresses }
      )
    end

    let(:helper_client) { double('helper_client') }
    let(:command_runner) { double('command_runner') }
    let(:system_profiler_wifi_data_reader) { ->(_timeout_in_secs) { system_profiler_wifi_data } }
    let(:system_profiler_wifi_data) { system_profiler_wifi_payload(current_network_name: 'ProfilerNet') }
    let(:wifi_on) { true }
    let(:wifi_interface) { 'en0' }
    let(:default_interface) { nil }
    let(:ipv4_addresses) { [] }
    let(:ipv6_addresses) { [] }

    def helper_result(**kwargs)
      WifiWand::Platforms::Mac::Helper::Bundle::HelperQueryResult.new(**kwargs)
    end

    def system_profiler_wifi_payload(current_network_name:, interface_name: 'en0')
      current_network = if current_network_name == :missing
        nil
      else
        { '_name' => current_network_name }
      end

      {
        'SPAirPortDataType' => [{
          'spairport_airport_interfaces' => [{
            '_name'                                 => interface_name,
            'spairport_current_network_information' => current_network,
          }],
        }],
      }
    end

    describe '#connected_network_name_raw' do
      it 'returns the helper-provided SSID before running fallback commands' do
        expect(helper_client).to receive(:connected_network_name)
          .and_return(helper_result(payload: 'HelperNet'))
        expect(command_runner).not_to receive(:call)

        expect(reader.connected_network_name_raw).to eq('HelperNet')
      end

      it 'uses networksetup before system_profiler WiFi data' do
        expect(helper_client).to receive(:connected_network_name).and_return(helper_result)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-getairportnetwork', wifi_interface], timeout_in_secs: nil)
          .and_return(command_result(stdout: "Current Wi-Fi Network: NetworksetupNet\n"))

        expect(reader.connected_network_name_raw).to eq('NetworksetupNet')
      end

      it 'falls through a networksetup placeholder SSID to system_profiler WiFi data' do
        expect(helper_client).to receive(:connected_network_name).and_return(helper_result)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-getairportnetwork', wifi_interface], timeout_in_secs: nil)
          .and_return(command_result(stdout: "Current Wi-Fi Network: <redacted>\n"))

        expect(reader.connected_network_name_raw).to eq('ProfilerNet')
      end

      it 'falls back to system_profiler WiFi data after helper and fast commands miss' do
        expect(helper_client).to receive(:connected_network_name).and_return(helper_result)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-getairportnetwork', wifi_interface], timeout_in_secs: nil)
          .and_return(command_result(stdout: ''))

        expect(reader.connected_network_name_raw).to eq('ProfilerNet')
      end

      it 'does not consult fallbacks when the helper reports not connected' do
        expect(helper_client).to receive(:connected_network_name)
          .and_return(helper_result(status: :not_connected))
        expect(command_runner).not_to receive(:call)

        expect(reader.connected_network_name_raw).to be_nil
      end

      it 'keeps no-network sentinel behavior internal to the reader' do
        expect(helper_client).to receive(:connected_network_name).and_return(helper_result)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-getairportnetwork', wifi_interface], timeout_in_secs: nil)
          .and_return(command_result(stdout: "You are not associated with an AirPort network.\n"))

        expect(reader.connected_network_name_raw).to be_nil
      end
    end

    describe '#connected_network_name' do
      it 'raises a redaction error when placeholder fallback identity has association evidence' do
        allow(reader).to receive(:connected?).and_return(true)
        expect(helper_client).to receive(:connected_network_name).once.and_return(helper_result)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-getairportnetwork', wifi_interface], timeout_in_secs: nil)
          .and_return(command_result(stdout: "Current Wi-Fi Network: <hidden>\n"))
        allow(system_profiler_wifi_data_reader).to receive(:call).and_return(
          system_profiler_wifi_payload(current_network_name: '<hidden>')
        )

        expect { reader.connected_network_name }.to raise_error(WifiWand::MacOsRedactionError)
      end

      it 'returns nil without redaction work after authoritative disconnection' do
        expect(helper_client).to receive(:connected_network_name).and_return(helper_result)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-getairportnetwork', wifi_interface], timeout_in_secs: nil)
          .and_return(command_result(stdout: "Wi-Fi power is currently off.\n"))

        expect(reader).not_to receive(:connected?)
        expect(reader.connected_network_name).to be_nil
      end
    end

    describe '#network_identity_redacted?' do
      it 'returns true when the helper reports a Location Services error' do
        expect(helper_client).to receive(:connected_network_name).and_return(
          helper_result(location_services_blocked: true)
        )

        expect(reader.network_identity_redacted?).to be(true)
      end

      it 'returns true when the helper returns a placeholder SSID' do
        expect(helper_client).to receive(:connected_network_name).and_return(
          helper_result(payload: '<redacted>')
        )

        expect(reader.network_identity_redacted?).to be(true)
      end

      it 'returns true when fallback identity is missing but association evidence exists' do
        no_current_network = system_profiler_wifi_payload(current_network_name: :missing)

        expect(helper_client).to receive(:connected_network_name).and_return(helper_result)
        allow(system_profiler_wifi_data_reader).to receive(:call).and_return(no_current_network)
        allow(reader).to receive(:associated_without_ssid?).and_return(true)

        expect(reader.network_identity_redacted?).to be(true)
      end

      it 'returns false when helper and fallback evidence do not indicate redaction' do
        expect(helper_client).to receive(:connected_network_name).and_return(helper_result)

        expect(reader.network_identity_redacted?).to be(false)
      end
    end

    describe '#network_identity_redaction_reason' do
      it 'returns the macOS helper Location Services guidance when identity is redacted' do
        allow(reader).to receive(:network_identity_redacted?).and_return(true)

        expect(reader.network_identity_redaction_reason).to include(
          'Location Services access is granted to wifiwand-helper'
        )
      end

      it 'returns nil when identity is not redacted' do
        allow(reader).to receive(:network_identity_redacted?).and_return(false)

        expect(reader.network_identity_redaction_reason).to be_nil
      end
    end

    describe '#connected?' do
      it 'ignores helper placeholder names and falls back to association without SSID' do
        allow(helper_client).to receive(:connected_network_name)
          .and_return(helper_result(payload: '<redacted>'))
        allow(command_runner).to receive(:call)
        allow(system_profiler_wifi_data_reader).to receive(:call).and_return(
          system_profiler_wifi_payload(current_network_name: :missing)
        )
        allow(reader).to receive(:associated_without_ssid?).and_return(true)

        expect(reader.connected?).to be(true)
      end

      context 'when only IPv6 address evidence is available' do
        let(:ipv6_addresses) { ['2001:db8::44'] }

        it 'treats the interface as associated when SSID identity is unavailable' do
          allow(helper_client).to receive(:connected_network_name).and_return(helper_result)
          allow(system_profiler_wifi_data_reader).to receive(:call).and_return(
            system_profiler_wifi_payload(current_network_name: :missing)
          )

          expect(reader.connected?).to be(true)
        end
      end

      context 'when only link-local IPv6 address evidence is available' do
        let(:ipv6_addresses) { ['fe80::1'] }

        it 'does not treat the interface as associated without stronger evidence' do
          allow(helper_client).to receive(:connected_network_name).and_return(helper_result)
          allow(system_profiler_wifi_data_reader).to receive(:call).and_return(
            system_profiler_wifi_payload(current_network_name: :missing)
          )

          expect(reader.connected?).to be(false)
        end
      end
    end

    describe '#associated?' do
      it 'is false when WiFi is off' do
        allow(reader).to receive(:wifi_on?).and_return(false)

        expect(reader.associated?).to be(false)
      end

      it 'is true when the helper reports a real SSID' do
        allow(helper_client).to receive(:connected_network_name)
          .and_return(helper_result(payload: 'HelperNet'))

        expect(reader.associated?).to be(true)
      end

      it 'is false when the helper says the interface is not connected' do
        allow(helper_client).to receive(:connected_network_name)
          .and_return(helper_result(status: :not_connected))

        expect(reader.associated?).to be(false)
      end

      it 'falls back to system_profiler association data when the helper is inconclusive' do
        allow(helper_client).to receive(:connected_network_name).and_return(helper_result)

        expect(reader.associated?).to be(true)
      end

      it 'is false when the helper query fails' do
        allow(helper_client).to receive(:connected_network_name)
          .and_raise(WifiWand::Error, 'helper unavailable')

        expect(reader.associated?).to be(false)
      end
    end

    describe '#connected_network_name without redaction' do
      it 'returns nil when the SSID is unknown but the interface does not look redacted' do
        allow(reader).to receive_messages(
          connected_network_name_raw:                      nil,
          connected_network_authoritatively_disconnected?: false,
          connected?:                                      false
        )

        expect(reader.connected_network_name).to be_nil
      end
    end

    describe '#network_identity_redacted? when the helper query fails' do
      it 'reports no redaction rather than raising' do
        allow(helper_client).to receive(:connected_network_name)
          .and_raise(WifiWand::Error, 'helper unavailable')

        expect(reader.network_identity_redacted?).to be(false)
      end
    end

    describe '#associated_without_ssid?' do
      it 'is true when the WiFi interface carries the default route' do
        allow(reader).to receive(:default_interface).and_return('en0')

        expect(reader.send(:associated_without_ssid?)).to be(true)
      end

      context 'when address lookup fails' do
        let(:default_interface) { 'en1' }
        let(:ipv4_addresses) do
          raise os_command_error(exitstatus: 1, command: 'ipconfig getifaddr en0', text: 'failed')
        end

        it 'treats the interface as not associated instead of raising' do
          expect(reader.send(:associated_without_ssid?)).to be(false)
        end
      end
    end

    describe '#usable_ipv6_association_address?' do
      {
        'a global unicast address'    => ['2001:db8::44', true],
        'a link-local address'        => ['fe80::1', false],
        'an IPv4 address'             => ['192.168.1.5', false],
        'text that is not an address' => ['not-an-ip', false],
      }.each do |description, (address, expected)|
        it "is #{expected} for #{description}" do
          expect(reader.send(:usable_ipv6_association_address?, address)).to be(expected)
        end
      end
    end
  end
end
