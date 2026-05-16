# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/platforms/mac/current_network_details'

module WifiWand
  describe Platforms::Mac::CurrentNetworkDetails do
    subject(:details) do
      described_class.new(
        system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
        system_profiler_wifi_data_cache_runner: cache_scope_runner,
        connected_network_name_reader:          -> { connected_network_name },
        wifi_interface_provider:                -> { wifi_interface },
        security_normalizer:                    security_normalizer
      )
    end

    let(:connected_network_name) { 'TestNetwork' }
    let(:wifi_interface) { 'en0' }
    let(:cache_scope_runner) { ->(&block) { block.call } }
    let(:security_normalizer) do
      ->(security_text) do
        return nil if security_text.match?(/802\.?1x|enterprise/i)

        case security_text
        when /WPA3/i
          'WPA3'
        when /WPA2/i
          'WPA2'
        when /WPA1/i, /WPA(?!\d)/i
          'WPA'
        when /WEP/i
          'WEP'
        when /\bnone\b|spairport_security_mode_none/i, /\bowe\b/i
          'NONE'
        end
      end
    end
    let(:system_profiler_wifi_data) { system_profiler_wifi_data_with_current_network(security_mode: 'WPA2') }

    def system_profiler_wifi_data_with_current_network(security_mode:, local_networks: [],
      other_local_networks: nil, signal_noise: '-65/-95')
      other_local_networks ||= [{
        '_name'                   => 'TestNetwork',
        'spairport_security_mode' => security_mode,
      }]

      {
        'SPAirPortDataType' => [{
          'spairport_airport_interfaces' => [{
            '_name'                                           => 'en0',
            'spairport_current_network_information'           => {
              '_name'                  => 'TestNetwork',
              'spairport_signal_noise' => signal_noise,
            },
            'spairport_airport_local_wireless_networks'       => local_networks,
            'spairport_airport_other_local_wireless_networks' => other_local_networks,
          }],
        }],
      }
    end

    def system_profiler_wifi_data_without_current_network(local_networks:)
      {
        'SPAirPortDataType' => [{
          'spairport_airport_interfaces' => [{
            '_name'                                     => 'en0',
            'spairport_airport_local_wireless_networks' => local_networks,
          }],
        }],
      }
    end

    describe '#connection_security_type' do
      [
        ['WPA3', 'WPA3'],
        ['WPA2', 'WPA2'],
        ['WPA1', 'WPA'],
        ['WPA', 'WPA'],
        ['WEP', 'WEP'],
        ['spairport_security_mode_none', 'NONE'],
        ['None', 'NONE'],
        ['OWE', 'NONE'],
        ['', 'NONE'],
        ['Unknown Security', nil],
        ['WPA2 Enterprise', nil],
      ].each do |security_mode, expected_result|
        mode_description = security_mode.empty? ? 'blank security mode' : security_mode

        it "returns #{expected_result || 'nil'} for #{mode_description}" do
          system_profiler_wifi_data = system_profiler_wifi_data_with_current_network(
            security_mode: security_mode
          )

          expect(
            described_class.new(
              system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
              system_profiler_wifi_data_cache_runner: cache_scope_runner,
              connected_network_name_reader:          -> { connected_network_name },
              wifi_interface_provider:                -> { wifi_interface },
              security_normalizer:                    security_normalizer
            ).connection_security_type
          ).to eq(expected_result)
        end
      end

      it 'reads the associated network list when system_profiler WiFi data marks the interface associated' do
        system_profiler_wifi_data = system_profiler_wifi_data_with_current_network(
          security_mode:        'WPA3',
          local_networks:       [{
            '_name'                   => connected_network_name,
            'spairport_security_mode' => 'WEP',
          }],
          other_local_networks: [{
            '_name'                   => connected_network_name,
            'spairport_security_mode' => 'WPA3',
          }]
        )

        expect(
          described_class.new(
            system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
            system_profiler_wifi_data_cache_runner: cache_scope_runner,
            connected_network_name_reader:          -> { connected_network_name },
            wifi_interface_provider:                -> { wifi_interface },
            security_normalizer:                    security_normalizer
          ).connection_security_type
        ).to eq('WPA3')
      end

      it 'reads the local network list when system_profiler WiFi data does not mark ' \
        'the interface associated' do
        system_profiler_wifi_data = system_profiler_wifi_data_without_current_network(
          local_networks: [{
            '_name'                   => connected_network_name,
            'spairport_security_mode' => 'WEP',
          }]
        )

        expect(
          described_class.new(
            system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
            system_profiler_wifi_data_cache_runner: cache_scope_runner,
            connected_network_name_reader:          -> { connected_network_name },
            wifi_interface_provider:                -> { wifi_interface },
            security_normalizer:                    security_normalizer
          ).connection_security_type
        ).to eq('WEP')
      end

      it 'returns nil when not connected to any network' do
        expect(
          described_class.new(
            system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
            system_profiler_wifi_data_cache_runner: cache_scope_runner,
            connected_network_name_reader:          -> {},
            wifi_interface_provider:                -> { wifi_interface },
            security_normalizer:                    security_normalizer
          ).connection_security_type
        ).to be_nil
      end

      it 'returns nil when the security field is missing' do
        system_profiler_wifi_data = system_profiler_wifi_data_with_current_network(
          security_mode:        'WPA2',
          other_local_networks: [{ '_name' => connected_network_name }]
        )

        expect(
          described_class.new(
            system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
            system_profiler_wifi_data_cache_runner: cache_scope_runner,
            connected_network_name_reader:          -> { connected_network_name },
            wifi_interface_provider:                -> { wifi_interface },
            security_normalizer:                    security_normalizer
          ).connection_security_type
        ).to be_nil
      end

      it 'returns nil when interface data is missing' do
        system_profiler_wifi_data = {
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name' => 'en1',
            }],
          }],
        }

        expect(
          described_class.new(
            system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
            system_profiler_wifi_data_cache_runner: cache_scope_runner,
            connected_network_name_reader:          -> { connected_network_name },
            wifi_interface_provider:                -> { wifi_interface },
            security_normalizer:                    security_normalizer
          ).connection_security_type
        ).to be_nil
      end

      it 'returns nil when profiler data is empty' do
        system_profiler_wifi_data = {}

        expect(
          described_class.new(
            system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
            system_profiler_wifi_data_cache_runner: cache_scope_runner,
            connected_network_name_reader:          -> { connected_network_name },
            wifi_interface_provider:                -> { wifi_interface },
            security_normalizer:                    security_normalizer
          ).connection_security_type
        ).to be_nil
      end

      it 'returns nil when profiler data is malformed' do
        system_profiler_wifi_data = { 'SPAirPortDataType' => 'not an array' }

        expect(
          described_class.new(
            system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
            system_profiler_wifi_data_cache_runner: cache_scope_runner,
            connected_network_name_reader:          -> { connected_network_name },
            wifi_interface_provider:                -> { wifi_interface },
            security_normalizer:                    security_normalizer
          ).connection_security_type
        ).to be_nil
      end
    end

    describe '#network_hidden?' do
      it 'returns true when the current network is absent from visible lists' do
        system_profiler_wifi_data = system_profiler_wifi_data_with_current_network(
          security_mode:        'WPA2',
          local_networks:       [{ '_name' => 'OtherNetwork' }],
          other_local_networks: []
        )

        expect(
          described_class.new(
            system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
            system_profiler_wifi_data_cache_runner: cache_scope_runner,
            connected_network_name_reader:          -> { connected_network_name },
            wifi_interface_provider:                -> { wifi_interface },
            security_normalizer:                    security_normalizer
          ).network_hidden?
        ).to be true
      end

      it 'returns false when the current network appears in local networks' do
        system_profiler_wifi_data = system_profiler_wifi_data_with_current_network(
          security_mode:  'WPA2',
          local_networks: [{ '_name' => connected_network_name }]
        )

        expect(
          described_class.new(
            system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
            system_profiler_wifi_data_cache_runner: cache_scope_runner,
            connected_network_name_reader:          -> { connected_network_name },
            wifi_interface_provider:                -> { wifi_interface },
            security_normalizer:                    security_normalizer
          ).network_hidden?
        ).to be false
      end

      it 'returns false when the current network appears in other local networks' do
        system_profiler_wifi_data = system_profiler_wifi_data_with_current_network(
          security_mode:        'WPA2',
          other_local_networks: [{ '_name' => connected_network_name }]
        )

        expect(
          described_class.new(
            system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
            system_profiler_wifi_data_cache_runner: cache_scope_runner,
            connected_network_name_reader:          -> { connected_network_name },
            wifi_interface_provider:                -> { wifi_interface },
            security_normalizer:                    security_normalizer
          ).network_hidden?
        ).to be false
      end

      it 'returns false when not connected to any network' do
        expect(
          described_class.new(
            system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
            system_profiler_wifi_data_cache_runner: cache_scope_runner,
            connected_network_name_reader:          -> {},
            wifi_interface_provider:                -> { wifi_interface },
            security_normalizer:                    security_normalizer
          ).network_hidden?
        ).to be false
      end

      it 'returns false when interface data is missing' do
        system_profiler_wifi_data = {
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name' => 'en1',
            }],
          }],
        }

        expect(
          described_class.new(
            system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
            system_profiler_wifi_data_cache_runner: cache_scope_runner,
            connected_network_name_reader:          -> { connected_network_name },
            wifi_interface_provider:                -> { wifi_interface },
            security_normalizer:                    security_normalizer
          ).network_hidden?
        ).to be false
      end

      it 'returns false when current network data is missing from system_profiler WiFi data' do
        system_profiler_wifi_data = system_profiler_wifi_data_without_current_network(
          local_networks: [{ '_name' => 'OtherNetwork' }]
        )

        expect(
          described_class.new(
            system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
            system_profiler_wifi_data_cache_runner: cache_scope_runner,
            connected_network_name_reader:          -> { connected_network_name },
            wifi_interface_provider:                -> { wifi_interface },
            security_normalizer:                    security_normalizer
          ).network_hidden?
        ).to be false
      end

      it 'returns false when profiler data is empty' do
        system_profiler_wifi_data = {}

        expect(
          described_class.new(
            system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
            system_profiler_wifi_data_cache_runner: cache_scope_runner,
            connected_network_name_reader:          -> { connected_network_name },
            wifi_interface_provider:                -> { wifi_interface },
            security_normalizer:                    security_normalizer
          ).network_hidden?
        ).to be false
      end

      it 'returns false when profiler data is malformed' do
        system_profiler_wifi_data = { 'SPAirPortDataType' => 'not an array' }

        expect(
          described_class.new(
            system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
            system_profiler_wifi_data_cache_runner: cache_scope_runner,
            connected_network_name_reader:          -> { connected_network_name },
            wifi_interface_provider:                -> { wifi_interface },
            security_normalizer:                    security_normalizer
          ).network_hidden?
        ).to be false
      end
    end

    describe '#signal_quality' do
      it 'returns current network signal quality in dBm' do
        signal_quality = details.signal_quality

        expect(signal_quality.value).to eq(-65)
        expect(signal_quality.unit).to eq(:dbm)
        expect(signal_quality.to_s).to eq('-65 dBm')
      end

      it 'returns nil when not connected to any network' do
        details = described_class.new(
          system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
          system_profiler_wifi_data_cache_runner: cache_scope_runner,
          connected_network_name_reader:          -> {},
          wifi_interface_provider:                -> { wifi_interface },
          security_normalizer:                    security_normalizer
        )

        expect(details.signal_quality).to be_nil
      end

      it 'preserves zero as a valid dBm reading' do
        system_profiler_wifi_data = system_profiler_wifi_data_with_current_network(
          security_mode: 'WPA2',
          signal_noise:  '0/-95'
        )
        details = described_class.new(
          system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
          system_profiler_wifi_data_cache_runner: cache_scope_runner,
          connected_network_name_reader:          -> { connected_network_name },
          wifi_interface_provider:                -> { wifi_interface },
          security_normalizer:                    security_normalizer
        )

        expect(details.signal_quality.to_s).to eq('0 dBm')
      end
    end

    it 'wraps lookups in the system_profiler WiFi data cache scope' do
      events = []
      cache_scope_runner = ->(&block) do
        events << :enter
        result = block.call
        events << :exit
        result
      end

      described_class.new(
        system_profiler_wifi_data_reader:       -> { system_profiler_wifi_data },
        system_profiler_wifi_data_cache_runner: cache_scope_runner,
        connected_network_name_reader:          -> { connected_network_name },
        wifi_interface_provider:                -> { wifi_interface },
        security_normalizer:                    security_normalizer
      ).connection_security_type

      expect(events).to eq(%i[enter exit])
    end
  end
end
