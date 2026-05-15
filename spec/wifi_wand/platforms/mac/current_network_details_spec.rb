# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/platforms/mac/current_network_details'

module WifiWand
  describe Platforms::Mac::CurrentNetworkDetails do
    subject(:details) do
      described_class.new(
        airport_data_proc:             -> { airport_data },
        airport_data_cache_scope_proc: cache_scope_proc,
        connected_network_name_proc:   -> { connected_network_name },
        wifi_interface_proc:           -> { wifi_interface },
        security_normalizer_proc:      security_normalizer
      )
    end

    let(:connected_network_name) { 'TestNetwork' }
    let(:wifi_interface) { 'en0' }
    let(:cache_scope_proc) { ->(&block) { block.call } }
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
    let(:airport_data) { airport_data_with_current_network(security_mode: 'WPA2') }

    def airport_data_with_current_network(security_mode:, local_networks: [], other_local_networks: nil)
      other_local_networks ||= [{
        '_name'                   => 'TestNetwork',
        'spairport_security_mode' => security_mode,
      }]

      {
        'SPAirPortDataType' => [{
          'spairport_airport_interfaces' => [{
            '_name'                                           => 'en0',
            'spairport_current_network_information'           => { '_name' => 'TestNetwork' },
            'spairport_airport_local_wireless_networks'       => local_networks,
            'spairport_airport_other_local_wireless_networks' => other_local_networks,
          }],
        }],
      }
    end

    def airport_data_without_current_network(local_networks:)
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
          airport_data = airport_data_with_current_network(security_mode: security_mode)

          expect(
            described_class.new(
              airport_data_proc:             -> { airport_data },
              airport_data_cache_scope_proc: cache_scope_proc,
              connected_network_name_proc:   -> { connected_network_name },
              wifi_interface_proc:           -> { wifi_interface },
              security_normalizer_proc:      security_normalizer
            ).connection_security_type
          ).to eq(expected_result)
        end
      end

      it 'reads the associated network list when Airport data marks the interface associated' do
        airport_data = airport_data_with_current_network(
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
            airport_data_proc:             -> { airport_data },
            airport_data_cache_scope_proc: cache_scope_proc,
            connected_network_name_proc:   -> { connected_network_name },
            wifi_interface_proc:           -> { wifi_interface },
            security_normalizer_proc:      security_normalizer
          ).connection_security_type
        ).to eq('WPA3')
      end

      it 'reads the local network list when Airport data does not mark the interface associated' do
        airport_data = airport_data_without_current_network(
          local_networks: [{
            '_name'                   => connected_network_name,
            'spairport_security_mode' => 'WEP',
          }]
        )

        expect(
          described_class.new(
            airport_data_proc:             -> { airport_data },
            airport_data_cache_scope_proc: cache_scope_proc,
            connected_network_name_proc:   -> { connected_network_name },
            wifi_interface_proc:           -> { wifi_interface },
            security_normalizer_proc:      security_normalizer
          ).connection_security_type
        ).to eq('WEP')
      end

      it 'returns nil when not connected to any network' do
        allow(details).to receive(:connected_network_name).and_return(nil)

        expect(details.connection_security_type).to be_nil
      end

      it 'returns nil when the security field is missing' do
        airport_data = airport_data_with_current_network(
          security_mode:        'WPA2',
          other_local_networks: [{ '_name' => connected_network_name }]
        )

        expect(
          described_class.new(
            airport_data_proc:             -> { airport_data },
            airport_data_cache_scope_proc: cache_scope_proc,
            connected_network_name_proc:   -> { connected_network_name },
            wifi_interface_proc:           -> { wifi_interface },
            security_normalizer_proc:      security_normalizer
          ).connection_security_type
        ).to be_nil
      end

      it 'returns nil when interface data is missing' do
        airport_data = {
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name' => 'en1',
            }],
          }],
        }

        expect(
          described_class.new(
            airport_data_proc:             -> { airport_data },
            airport_data_cache_scope_proc: cache_scope_proc,
            connected_network_name_proc:   -> { connected_network_name },
            wifi_interface_proc:           -> { wifi_interface },
            security_normalizer_proc:      security_normalizer
          ).connection_security_type
        ).to be_nil
      end

      it 'returns nil when profiler data is empty' do
        airport_data = {}

        expect(
          described_class.new(
            airport_data_proc:             -> { airport_data },
            airport_data_cache_scope_proc: cache_scope_proc,
            connected_network_name_proc:   -> { connected_network_name },
            wifi_interface_proc:           -> { wifi_interface },
            security_normalizer_proc:      security_normalizer
          ).connection_security_type
        ).to be_nil
      end

      it 'returns nil when profiler data is malformed' do
        airport_data = { 'SPAirPortDataType' => 'not an array' }

        expect(
          described_class.new(
            airport_data_proc:             -> { airport_data },
            airport_data_cache_scope_proc: cache_scope_proc,
            connected_network_name_proc:   -> { connected_network_name },
            wifi_interface_proc:           -> { wifi_interface },
            security_normalizer_proc:      security_normalizer
          ).connection_security_type
        ).to be_nil
      end
    end

    describe '#network_hidden?' do
      it 'returns true when the current network is absent from visible lists' do
        airport_data = airport_data_with_current_network(
          security_mode:        'WPA2',
          local_networks:       [{ '_name' => 'OtherNetwork' }],
          other_local_networks: []
        )

        expect(
          described_class.new(
            airport_data_proc:             -> { airport_data },
            airport_data_cache_scope_proc: cache_scope_proc,
            connected_network_name_proc:   -> { connected_network_name },
            wifi_interface_proc:           -> { wifi_interface },
            security_normalizer_proc:      security_normalizer
          ).network_hidden?
        ).to be true
      end

      it 'returns false when the current network appears in local networks' do
        airport_data = airport_data_with_current_network(
          security_mode:  'WPA2',
          local_networks: [{ '_name' => connected_network_name }]
        )

        expect(
          described_class.new(
            airport_data_proc:             -> { airport_data },
            airport_data_cache_scope_proc: cache_scope_proc,
            connected_network_name_proc:   -> { connected_network_name },
            wifi_interface_proc:           -> { wifi_interface },
            security_normalizer_proc:      security_normalizer
          ).network_hidden?
        ).to be false
      end

      it 'returns false when the current network appears in other local networks' do
        airport_data = airport_data_with_current_network(
          security_mode:        'WPA2',
          other_local_networks: [{ '_name' => connected_network_name }]
        )

        expect(
          described_class.new(
            airport_data_proc:             -> { airport_data },
            airport_data_cache_scope_proc: cache_scope_proc,
            connected_network_name_proc:   -> { connected_network_name },
            wifi_interface_proc:           -> { wifi_interface },
            security_normalizer_proc:      security_normalizer
          ).network_hidden?
        ).to be false
      end

      it 'returns false when not connected to any network' do
        allow(details).to receive(:connected_network_name).and_return(nil)

        expect(details.network_hidden?).to be false
      end

      it 'returns false when interface data is missing' do
        airport_data = {
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name' => 'en1',
            }],
          }],
        }

        expect(
          described_class.new(
            airport_data_proc:             -> { airport_data },
            airport_data_cache_scope_proc: cache_scope_proc,
            connected_network_name_proc:   -> { connected_network_name },
            wifi_interface_proc:           -> { wifi_interface },
            security_normalizer_proc:      security_normalizer
          ).network_hidden?
        ).to be false
      end

      it 'returns false when current network data is missing from Airport data' do
        airport_data = airport_data_without_current_network(
          local_networks: [{ '_name' => 'OtherNetwork' }]
        )

        expect(
          described_class.new(
            airport_data_proc:             -> { airport_data },
            airport_data_cache_scope_proc: cache_scope_proc,
            connected_network_name_proc:   -> { connected_network_name },
            wifi_interface_proc:           -> { wifi_interface },
            security_normalizer_proc:      security_normalizer
          ).network_hidden?
        ).to be false
      end

      it 'returns false when profiler data is empty' do
        airport_data = {}

        expect(
          described_class.new(
            airport_data_proc:             -> { airport_data },
            airport_data_cache_scope_proc: cache_scope_proc,
            connected_network_name_proc:   -> { connected_network_name },
            wifi_interface_proc:           -> { wifi_interface },
            security_normalizer_proc:      security_normalizer
          ).network_hidden?
        ).to be false
      end

      it 'returns false when profiler data is malformed' do
        airport_data = { 'SPAirPortDataType' => 'not an array' }

        expect(
          described_class.new(
            airport_data_proc:             -> { airport_data },
            airport_data_cache_scope_proc: cache_scope_proc,
            connected_network_name_proc:   -> { connected_network_name },
            wifi_interface_proc:           -> { wifi_interface },
            security_normalizer_proc:      security_normalizer
          ).network_hidden?
        ).to be false
      end
    end

    it 'wraps lookups in the Airport data cache scope' do
      events = []
      cache_scope_proc = ->(&block) do
        events << :enter
        result = block.call
        events << :exit
        result
      end

      described_class.new(
        airport_data_proc:             -> { airport_data },
        airport_data_cache_scope_proc: cache_scope_proc,
        connected_network_name_proc:   -> { connected_network_name },
        wifi_interface_proc:           -> { wifi_interface },
        security_normalizer_proc:      security_normalizer
      ).connection_security_type

      expect(events).to eq(%i[enter exit])
    end
  end
end
