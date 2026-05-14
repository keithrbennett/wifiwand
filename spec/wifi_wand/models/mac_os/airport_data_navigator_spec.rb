# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/models/mac_os/airport_data_navigator'

module WifiWand
  describe MacOsAirportDataNavigator do
    subject(:navigator) { described_class.new(airport_data) }

    let(:airport_data) do
      {
        'SPAirPortDataType' => [{
          'spairport_airport_interfaces' => [{
            '_name'                                           => 'en0',
            'spairport_airport_local_wireless_networks'       => [
              { '_name' => 'WeakNetwork', 'spairport_signal_noise' => '45/10' },
              { '_name' => '<hidden>', 'spairport_signal_noise' => '95/10' },
              { '_name' => 'StrongNetwork', 'spairport_signal_noise' => '85/10' },
              { '_name' => '<redacted>', 'spairport_signal_noise' => '75/10' },
              { '_name' => 'StrongNetwork', 'spairport_signal_noise' => '65/10' },
            ],
            'spairport_airport_other_local_wireless_networks' => [
              {
                '_name'                   => 'CurrentNetwork',
                'spairport_signal_noise'  => '80/10',
                'spairport_security_mode' => 'WPA2',
              },
              {
                '_name'                   => 'NeighborNetwork',
                'spairport_signal_noise'  => '50/10',
                'spairport_security_mode' => '',
              },
            ],
            'spairport_current_network_information'           => { '_name' => 'CurrentNetwork' },
          }],
        }],
      }
    end

    describe '.placeholder_network_name?' do
      [
        ['', true],
        ['   ', true],
        ['<hidden>', true],
        ['<HIDDEN>', true],
        ['<redacted>', true],
        ['<REDACTED>', true],
        ['VisibleNetwork', false],
      ].each do |network_name, expected_result|
        it "returns #{expected_result} for #{network_name.inspect}" do
          expect(described_class.placeholder_network_name?(network_name)).to eq(expected_result)
        end
      end
    end

    describe '.associated?' do
      it 'returns false for nil interface data' do
        expect(described_class.associated?(nil)).to be(false)
      end

      it 'returns false for empty current network hashes' do
        interface_data = {
          'spairport_current_network_information' => {},
        }

        expect(described_class.associated?(interface_data)).to be(false)
      end

      it 'returns true for non-empty current network hashes' do
        interface_data = {
          'spairport_current_network_information' => { '_name' => 'CurrentNetwork' },
        }

        expect(described_class.associated?(interface_data)).to be(true)
      end

      it 'returns true for non-empty current network strings' do
        interface_data = {
          'spairport_current_network_information' => 'CurrentNetwork',
        }

        expect(described_class.associated?(interface_data)).to be(true)
      end
    end

    describe '.current_network_name' do
      it 'returns a visible network name when placeholder filtering is enabled' do
        interface_data = {
          'spairport_current_network_information' => { '_name' => 'VisibleNetwork' },
        }

        expect(described_class.current_network_name(interface_data)).to eq('VisibleNetwork')
      end

      it 'returns placeholder names when requested' do
        interface_data = {
          'spairport_current_network_information' => { '_name' => '<hidden>' },
        }

        expect(
          described_class.current_network_name(interface_data, include_placeholder: true)
        ).to eq('<hidden>')
      end
    end

    describe '.current_network_present?' do
      it 'returns false for nil interface data' do
        expect(described_class.current_network_present?(nil)).to be(false)
      end

      it 'returns true when the current network key exists with an empty hash' do
        interface_data = {
          'spairport_current_network_information' => {},
        }

        expect(described_class.current_network_present?(interface_data)).to be(true)
        expect(described_class.associated?(interface_data)).to be(false)
      end
    end

    describe '.sorted_network_names' do
      it 'sorts network hashes by signal strength and filters placeholders and duplicates' do
        networks = [
          { '_name' => 'WeakNetwork', 'spairport_signal_noise' => '45/10' },
          { '_name' => '<hidden>', 'spairport_signal_noise' => '95/10' },
          { '_name' => 'StrongNetwork', 'spairport_signal_noise' => '85/10' },
          { '_name' => 'StrongNetwork', 'spairport_signal_noise' => '65/10' },
          { '_name' => nil, 'spairport_signal_noise' => '55/10' },
        ]

        expect(described_class.sorted_network_names(networks)).to eq(%w[StrongNetwork WeakNetwork])
      end

      it 'returns an empty list for malformed network lists' do
        expect(described_class.sorted_network_names('invalid')).to eq([])
      end
    end

    describe '.signal_strength' do
      it 'extracts the signal component from signal/noise data' do
        network = { 'spairport_signal_noise' => '-65/-95' }

        expect(described_class.signal_strength(network)).to eq(-65)
      end

      it 'defaults to zero when signal/noise data is missing or malformed' do
        expect(described_class.signal_strength({})).to eq(0)
        expect(described_class.signal_strength('invalid')).to eq(0)
      end
    end

    describe '#interfaces' do
      it 'returns Airport interfaces from the system profiler payload' do
        expect(navigator.interfaces).to contain_exactly(include('_name' => 'en0'))
      end

      it 'returns an empty list for malformed profiler data' do
        malformed_navigator = described_class.new('SPAirPortDataType' => ['invalid'])

        expect(malformed_navigator.interfaces).to eq([])
      end

      it 'returns an empty list when the profiler interfaces value is malformed' do
        malformed_navigator = described_class.new(
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => 'invalid',
          }]
        )

        expect(malformed_navigator.interfaces).to eq([])
      end
    end

    describe '#interface_data' do
      it 'finds data for the requested interface' do
        expect(navigator.interface_data('en0')).to include('_name' => 'en0')
      end

      it 'returns nil when the interface is absent' do
        expect(navigator.interface_data('en1')).to be_nil
      end

      it 'returns nil when malformed interface entries are present' do
        malformed_navigator = described_class.new(
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => ['invalid'],
          }]
        )

        expect(malformed_navigator.interface_data('en0')).to be_nil
      end
    end

    describe '#current_network_name' do
      it 'reads the associated network name from current network information' do
        expect(navigator.current_network_name('en0')).to eq('CurrentNetwork')
      end

      it 'uses placeholder filtering by default' do
        placeholder_navigator = described_class.new(
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                 => 'en0',
              'spairport_current_network_information' => { '_name' => '<hidden>' },
            }],
          }]
        )

        expect(placeholder_navigator.current_network_name('en0')).to be_nil
      end

      it 'filters placeholder names unless placeholders are requested' do
        placeholder_navigator = described_class.new(
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                 => 'en0',
              'spairport_current_network_information' => { '_name' => '<redacted>' },
            }],
          }]
        )

        expect(placeholder_navigator.current_network_name('en0')).to be_nil
        expect(
          placeholder_navigator.current_network_name('en0', include_placeholder: true)
        ).to eq('<redacted>')
      end
    end

    describe '#associated?' do
      it 'returns true for non-empty current network hashes' do
        expect(navigator.associated?('en0')).to be(true)
      end

      it 'delegates missing interfaces to the class association check' do
        expect(navigator.associated?('en1')).to be(false)
      end

      it 'returns false for missing or empty current network information' do
        empty_navigator = described_class.new(
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                 => 'en0',
              'spairport_current_network_information' => {},
            }],
          }]
        )

        expect(empty_navigator.associated?('en0')).to be(false)
        expect(empty_navigator.associated?('en1')).to be(false)
      end
    end

    describe '#current_network_present?' do
      it 'returns true when current network information is present' do
        expect(navigator.current_network_present?('en0')).to be(true)
      end

      it 'returns true when the current network key exists with an empty hash' do
        empty_current_network_navigator = described_class.new(
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                 => 'en0',
              'spairport_current_network_information' => {},
            }],
          }]
        )

        expect(empty_current_network_navigator.current_network_present?('en0')).to be(true)
        expect(empty_current_network_navigator.associated?('en0')).to be(false)
      end

      it 'returns false when current network information is missing' do
        missing_current_network_navigator = described_class.new(
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name' => 'en0',
            }],
          }]
        )

        expect(missing_current_network_navigator.current_network_present?('en0')).to be(false)
      end
    end

    describe '#visible_networks' do
      it 'returns raw network hashes from the associated network list' do
        expect(navigator.visible_networks('en0')).to eq(
          [
            {
              '_name'                   => 'CurrentNetwork',
              'spairport_signal_noise'  => '80/10',
              'spairport_security_mode' => 'WPA2',
            },
            {
              '_name'                   => 'NeighborNetwork',
              'spairport_signal_noise'  => '50/10',
              'spairport_security_mode' => '',
            },
          ]
        )
      end

      it 'returns raw network hashes from the unassociated network list when requested' do
        expect(navigator.visible_networks('en0', associated: false)).to include(
          { '_name' => 'StrongNetwork', 'spairport_signal_noise' => '85/10' },
          { '_name' => 'WeakNetwork', 'spairport_signal_noise' => '45/10' }
        )
      end

      it 'returns an empty list when profiler network lists are malformed' do
        malformed_navigator = described_class.new(
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                     => 'en0',
              'spairport_airport_local_wireless_networks' => 'invalid',
            }],
          }]
        )

        expect(malformed_navigator.visible_networks('en0')).to eq([])
      end
    end

    describe '#visible_network_names' do
      it 'uses associated network lists when the interface is associated' do
        expect(navigator.visible_network_names('en0')).to eq(%w[CurrentNetwork NeighborNetwork])
      end

      it 'delegates raw visible networks through sorted network name normalization' do
        expect(navigator.visible_network_names('en0', associated: false)).to eq(%w[StrongNetwork WeakNetwork])
      end

      it 'returns an empty list when the interface or network list is missing' do
        expect(navigator.visible_network_names('en1')).to eq([])
      end

      it 'returns an empty list when profiler network lists are malformed' do
        malformed_navigator = described_class.new(
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                     => 'en0',
              'spairport_airport_local_wireless_networks' => 'invalid',
            }],
          }]
        )

        expect(malformed_navigator.visible_network_names('en0')).to eq([])
      end
    end

    describe '#network_security' do
      it 'extracts security information from the selected visible network list' do
        expect(navigator.network_security('en0', 'CurrentNetwork')).to eq('WPA2')
      end

      it 'preserves blank open-network security values for callers to canonicalize' do
        expect(navigator.network_security('en0', 'NeighborNetwork')).to eq('')
      end

      it 'returns nil when the requested network is absent' do
        expect(navigator.network_security('en0', 'MissingNetwork')).to be_nil
      end
    end

    describe '#network_hidden?' do
      it 'returns false when the connected network appears in either profiler network list' do
        expect(navigator.network_hidden?('en0', 'CurrentNetwork')).to be(false)
      end

      it 'returns false when the network appears only in the non-preferred profiler list' do
        expect(navigator.network_hidden?('en0', 'StrongNetwork')).to be(false)
      end

      it 'returns true when current network information exists but the network is absent from scan lists' do
        expect(navigator.network_hidden?('en0', 'HiddenNetwork')).to be(true)
      end

      it 'does not raise when profiler network lists are malformed' do
        malformed_navigator = described_class.new(
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                           => 'en0',
              'spairport_current_network_information'           => { '_name' => 'CurrentNetwork' },
              'spairport_airport_local_wireless_networks'       => [
                { '_name' => 'VisibleNetwork', 'spairport_signal_noise' => '55/10' },
              ],
              'spairport_airport_other_local_wireless_networks' => 'invalid',
            }],
          }]
        )

        expect(malformed_navigator.network_hidden?('en0', 'VisibleNetwork')).to be(false)
      end

      it 'returns false when current network information is missing' do
        no_current_network_navigator = described_class.new(
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                     => 'en0',
              'spairport_airport_local_wireless_networks' => [
                { '_name' => 'OtherNetwork', 'spairport_signal_noise' => '40/10' },
              ],
            }],
          }]
        )

        expect(no_current_network_navigator.network_hidden?('en0', 'HiddenNetwork')).to be(false)
      end
    end
  end
end
