# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/status_line_data_builder'

describe WifiWand::StatusLineDataBuilder do
  let(:model) do
    double('model',
      wifi_on?:                   true,
      connected?:                 true,
      connected_network_name:     'HomeNetwork',
      internet_tcp_connectivity?: true,
      dns_working?:               true,
      captive_portal_state:       :free
    )
  end

  let(:progress_updates) { [] }
  let(:builder) { described_class.new(model, verbose: false, output: StringIO.new) }

  describe '#call' do
    it 'builds full status data and streams partial updates' do
      result = builder.call(progress_callback: ->(data) { progress_updates << data })

      expect(result).to eq(
        wifi_on:                       true,
        dns_working:                   true,
        connected:                     true,
        internet_state:                :reachable,
        internet_check_complete:       true,
        network_name:                  'HomeNetwork',
        captive_portal_state:          :free,
        captive_portal_login_required: :no
      )
      expect(progress_updates).to eq([
        { wifi_on: true, dns_working: nil, internet_state: :pending, internet_check_complete: false,
          connected: :pending, network_name: :pending, captive_portal_state: :indeterminate,
          captive_portal_login_required: :unknown },
        { wifi_on: true, dns_working: nil, internet_state: :pending, internet_check_complete: false,
          connected: true, network_name: 'HomeNetwork', captive_portal_state: :indeterminate,
          captive_portal_login_required: :unknown },
        { wifi_on: true, dns_working: true, connected: true, internet_state: :reachable,
          internet_check_complete: true, network_name: 'HomeNetwork', captive_portal_state: :free,
          captive_portal_login_required: :no },
      ])
    end

    it 'returns the wifi-off status without running internet checks' do
      allow(model).to receive(:wifi_on?).and_return(false)
      expect(model).not_to receive(:connected_network_name)
      expect(model).not_to receive(:connected?)
      expect(model).not_to receive(:internet_tcp_connectivity?)

      result = builder.call

      expect(result).to eq(
        wifi_on:                       false,
        dns_working:                   false,
        connected:                     false,
        internet_state:                :unreachable,
        internet_check_complete:       true,
        network_name:                  nil,
        captive_portal_state:          :indeterminate,
        captive_portal_login_required: :no
      )
    end

    it 'marks captive portal login required when portal detection succeeds' do
      allow(model).to receive_messages(
        internet_tcp_connectivity?: true,
        dns_working?:               true,
        captive_portal_state:       :present
      )

      result = builder.call

      expect(result[:dns_working]).to be true
      expect(result[:internet_state]).to eq(:unreachable)
      expect(result[:captive_portal_state]).to eq(:present)
      expect(result[:captive_portal_login_required]).to eq(:yes)
    end

    it 'preserves an indeterminate captive portal result when TCP and DNS succeed' do
      allow(model).to receive_messages(
        internet_tcp_connectivity?: true,
        dns_working?:               true,
        captive_portal_state:       :indeterminate
      )

      result = builder.call

      expect(result[:dns_working]).to be true
      expect(result[:internet_state]).to eq(:indeterminate)
      expect(result[:internet_check_complete]).to be true
      expect(result[:captive_portal_state]).to eq(:indeterminate)
      expect(result[:captive_portal_login_required]).to eq(:unknown)
    end

    it 'marks captive portal login as not required when TCP or DNS fails' do
      allow(model).to receive_messages(internet_tcp_connectivity?: false, dns_working?: false)

      result = builder.call

      expect(result[:dns_working]).to be false
      expect(result[:internet_state]).to eq(:unreachable)
      expect(result[:internet_check_complete]).to be true
      expect(result[:captive_portal_state]).to eq(:indeterminate)
      expect(result[:captive_portal_login_required]).to eq(:no)
    end

    it 'preserves successful DNS status when TCP connectivity fails' do
      allow(model).to receive_messages(internet_tcp_connectivity?: false, dns_working?: true)

      result = builder.call

      expect(result[:dns_working]).to be true
      expect(result[:internet_state]).to eq(:unreachable)
      expect(result[:internet_check_complete]).to be true
      expect(result[:captive_portal_state]).to eq(:indeterminate)
      expect(result[:captive_portal_login_required]).to eq(:no)
    end

    it 'returns nil and emits a nil progress update when the initial wifi check fails' do
      output = StringIO.new
      failing_builder = described_class.new(model, verbose: true, output: output)
      allow(model).to receive(:wifi_on?).and_raise(WifiWand::Error, 'boom')

      result = failing_builder.call(progress_callback: ->(data) { progress_updates << data })

      expect(result).to be_nil
      expect(progress_updates).to eq([nil])
      expect(output.string).to include('Warning: status_line_data failed: WifiWand::Error: boom')
    end

    it 'reports connected with SSID unavailable when connected? is true but the SSID is nil' do
      allow(model).to receive_messages(connected?: true, connected_network_name: nil)

      result = builder.call

      expect(result[:connected]).to be(true)
      expect(result[:network_name]).to eq('[SSID unavailable]')
    end

    it 'reports disconnected when connected? is false and the SSID is nil' do
      allow(model).to receive_messages(connected?: false, connected_network_name: nil)

      result = builder.call

      expect(result[:connected]).to be(false)
      expect(result[:network_name]).to be_nil
    end
  end
end
