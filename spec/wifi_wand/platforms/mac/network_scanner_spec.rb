# frozen_string_literal: true

require 'json'

require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/platforms/mac/helper/bundle'
require_relative '../../../../lib/wifi_wand/platforms/mac/network_scanner'

module WifiWand
  describe Platforms::Mac::NetworkScanner do
    subject(:scanner) do
      described_class.new(
        helper_client_proc:                         -> { helper_client },
        system_profiler_wifi_data_proc:             -> { system_profiler_wifi_data_reader.call },
        system_profiler_wifi_data_cache_scope_proc: ->(&block) { cache_scope.call(&block) },
        wifi_interface_proc:                        -> { 'en0' }
      )
    end

    let(:helper_client) { instance_double(WifiWand::Platforms::Mac::Helper::Client) }
    let(:system_profiler_wifi_data_reader) { double('system_profiler_wifi_data_reader') }
    let(:cache_scope) { double('cache_scope') }
    let(:system_profiler_wifi_data) do
      {
        'SPAirPortDataType' => [{
          'spairport_airport_interfaces' => [{
            '_name'                                     => 'en0',
            'spairport_airport_local_wireless_networks' => [
              { '_name' => 'WeakNetwork', 'spairport_signal_noise' => '-80/-95' },
              { '_name' => '<hidden>', 'spairport_signal_noise' => '-20/-95' },
              { '_name' => 'StrongNetwork', 'spairport_signal_noise' => '-45/-95' },
              { '_name' => 'MediumNetwork', 'spairport_signal_noise' => '-65/-95' },
              { '_name' => 'StrongNetwork', 'spairport_signal_noise' => '-70/-95' },
            ],
          }],
        }],
      }
    end

    before do
      allow(system_profiler_wifi_data_reader).to receive(:call).and_return(system_profiler_wifi_data)
      allow(cache_scope).to receive(:call).and_yield
    end

    def helper_result(**kwargs)
      WifiWand::Platforms::Mac::Helper::Bundle::HelperQueryResult.new(**kwargs)
    end

    describe '#scan' do
      it 'returns helper networks with trusted helper metadata when the helper succeeds' do
        allow(helper_client).to receive(:scan_networks).and_return(
          helper_result(
            payload: [
              { 'ssid' => 'Cafe WiFi' },
              { 'ssid' => '<hidden>' },
              { 'ssid' => 'Cafe WiFi' },
              { 'ssid' => 'Library WiFi' },
            ]
          )
        )

        expect(scanner.scan).to eq(
          'networks'          => ['Cafe WiFi', 'Library WiFi'],
          'scan_status'       => 'ok',
          'scan_source'       => 'mac_helper',
          'ssid_data_trusted' => true,
          'warning'           => nil
        )
      end

      it 'falls back to system_profiler networks sorted by signal strength' do
        allow(helper_client).to receive(:scan_networks).and_return(helper_result(payload: []))

        expect(scanner.scan).to include(
          'networks'          => %w[StrongNetwork MediumNetwork WeakNetwork],
          'scan_status'       => 'ok',
          'scan_source'       => 'fallback',
          'ssid_data_trusted' => true,
          'warning'           => nil
        )
      end

      it 'uses other local networks from system_profiler when the interface is associated' do
        connected_data = JSON.parse(JSON.generate(system_profiler_wifi_data))
        interface_data = connected_data['SPAirPortDataType'][0]['spairport_airport_interfaces'][0]
        interface_data['spairport_airport_other_local_wireless_networks'] = [
          { '_name' => 'CurrentNetwork', 'spairport_signal_noise' => '-40/-95' },
          { '_name' => 'NeighborNetwork', 'spairport_signal_noise' => '-70/-95' },
        ]
        interface_data['spairport_current_network_information'] = { '_name' => 'CurrentNetwork' }
        allow(helper_client).to receive(:scan_networks).and_return(helper_result(payload: []))
        allow(system_profiler_wifi_data_reader).to receive(:call).and_return(connected_data)

        expect(scanner.scan.fetch('networks')).to eq(%w[CurrentNetwork NeighborNetwork])
      end

      it 'marks fallback scan data as degraded when Location Services blocks helper SSIDs' do
        allow(helper_client).to receive(:scan_networks).and_return(
          helper_result(
            payload:                   [{ 'ssid' => 'HelperNetwork' }],
            location_services_blocked: true,
            error_message:             'Location Services denied'
          )
        )

        scan = scanner.scan

        expect(scan).to include(
          'networks'          => %w[StrongNetwork MediumNetwork WeakNetwork],
          'scan_status'       => 'location_services_blocked',
          'scan_source'       => 'fallback',
          'ssid_data_trusted' => false
        )
        expect(scan.fetch('warning')).to include('Location Services')
        expect(scan.fetch('warning')).to include('wifi-wand-macos-setup')
      end

      it 'preserves warning metadata even when degraded fallback has no networks' do
        empty_system_profiler_wifi_data = {
          'SPAirPortDataType' => [{
            'spairport_airport_interfaces' => [{
              '_name'                                     => 'en0',
              'spairport_airport_local_wireless_networks' => [],
            }],
          }],
        }
        allow(helper_client).to receive(:scan_networks).and_return(
          helper_result(location_services_blocked: true, error_message: 'Location Services denied')
        )
        allow(system_profiler_wifi_data_reader).to receive(:call).and_return(empty_system_profiler_wifi_data)

        expect(scanner.scan).to include(
          'networks'          => [],
          'scan_status'       => 'location_services_blocked',
          'scan_source'       => 'fallback',
          'ssid_data_trusted' => false
        )
      end
    end

    describe '#helper_available_network_names' do
      it 'returns nil when helper data only contains placeholder SSIDs' do
        allow(helper_client).to receive(:scan_networks).and_return(
          helper_result(payload: [{ 'ssid' => '<hidden>' }, { 'ssid' => '<redacted>' }])
        )

        expect(scanner.helper_available_network_names).to be_nil
      end
    end
  end
end
