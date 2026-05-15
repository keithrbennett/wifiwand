# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/avail_nets'

describe WifiWand::Commands::AvailNets do
  let(:mock_model) { double('Model') }
  let(:output_support) { double('output_support') }
  let(:cli) do
    double('cli', model: mock_model, output_support: output_support,
      help_hint: "Use 'wifi-wand help' or 'wifi-wand -h' for help.")
  end

  it_behaves_like 'binds command context',
    bound_attributes: { model: :mock_model, output_support: :output_support }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand avail_nets',
    description: 'descending signal-strength order'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes available network output through handle_output' do
      allow(mock_model).to receive(:available_network_names).and_return(%w[TestNet1 TestNet2])
      allow(mock_model).to receive(:respond_to?).with(:available_network_scan).and_return(false)
      allow(output_support).to receive(:format_object)
        .with(%w[TestNet1 TestNet2])
        .and_return("TestNet1\nTestNet2")
      expect(output_support).to receive(:handle_output) do |info, producer|
        expect(info).to include(
          'networks'          => %w[TestNet1 TestNet2],
          'scan_status'       => 'ok',
          'ssid_data_trusted' => true
        )
        rendered = producer.call
        expect(rendered).to include('Available networks, in descending signal strength order')
        expect(rendered).to include('TestNet1')
        expect(rendered).to include('TestNet2')
      end

      command.call
    end

    it 'uses the empty-available-networks message when the scan is empty' do
      allow(mock_model).to receive(:available_network_names).and_return([])
      allow(mock_model).to receive(:respond_to?).with(:available_network_scan).and_return(false)
      allow(output_support).to receive(:available_networks_empty_message)
        .and_return('No visible networks were found.')
      expect(output_support).to receive(:handle_output) do |info, producer|
        expect(info).to include('networks' => [], 'scan_status' => 'ok')
        expect(producer.call).to eq('No visible networks were found.')
      end

      command.call
    end

    it 'renders helper-blocked fallback data as degraded instead of authoritative' do
      warning = 'macOS blocked wifiwand-helper from reading WiFi SSIDs through Location Services'
      scan = {
        'networks'          => ['VisibleNetwork'],
        'scan_status'       => 'location_services_blocked',
        'scan_source'       => 'fallback',
        'ssid_data_trusted' => false,
        'warning'           => warning,
      }
      allow(mock_model).to receive(:available_network_scan).and_return(scan)
      allow(mock_model).to receive(:respond_to?).with(:available_network_scan).and_return(true)
      allow(output_support).to receive(:format_object)
        .with(['VisibleNetwork'])
        .and_return("VisibleNetwork\n")

      expect(output_support).to receive(:handle_output) do |info, producer|
        expect(info).to eq(scan)
        rendered = producer.call
        expect(rendered).to include('Warning: macOS blocked wifiwand-helper')
        expect(rendered).to include('Fallback scan results, which may be incomplete')
        expect(rendered).to include('VisibleNetwork')
      end

      command.call
    end

    it 'renders helper-blocked empty fallback data as unavailable' do
      warning = 'macOS blocked wifiwand-helper from reading WiFi SSIDs through Location Services'
      scan = {
        'networks'          => [],
        'scan_status'       => 'location_services_blocked',
        'scan_source'       => 'fallback',
        'ssid_data_trusted' => false,
        'warning'           => warning,
      }
      allow(mock_model).to receive(:available_network_scan).and_return(scan)
      allow(mock_model).to receive(:respond_to?).with(:available_network_scan).and_return(true)

      expect(output_support).to receive(:handle_output) do |info, producer|
        expect(info).to eq(scan)
        rendered = producer.call
        expect(rendered).to include('Warning: macOS blocked wifiwand-helper')
        expect(rendered).to include('No trustworthy visible network names')
      end

      command.call
    end

    it 'propagates model errors for CLI-level error handling' do
      allow(mock_model).to receive(:available_network_names)
        .and_raise(WifiWand::Error.new('WiFi is off, cannot scan for available networks.'))
      allow(mock_model).to receive(:respond_to?).with(:available_network_scan).and_return(false)

      expect { command.call }
        .to raise_error(WifiWand::Error, 'WiFi is off, cannot scan for available networks.')
    end

    it 'raises a usage-oriented error when extra arguments are provided' do
      expect(mock_model).not_to receive(:available_network_scan)
      expect(mock_model).not_to receive(:available_network_names)

      expect { command.call('extra') }
        .to raise_error(WifiWand::ConfigurationError) { |error|
          expect(error.message).to include('Unexpected argument(s): extra')
          expect(error.message).to include('Usage: wifi-wand avail_nets')
          expect(error.message).to include("Use 'wifi-wand help' or 'wifi-wand -h' for help.")
        }
    end
  end
end
