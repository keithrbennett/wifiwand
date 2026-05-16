# frozen_string_literal: true

require 'open3'

require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/platforms/mac/helper/bundle'
require_relative '../../../../lib/wifi_wand/platforms/mac/status_queries'

module WifiWand
  describe Platforms::Mac::StatusQueries do
    let(:wifi_interface_store) { { value: 'en0' } }
    let(:system_network_info) { double('system_network_info') }
    let(:status_timeout) { be_between(0, 0.5).inclusive }
    let(:wifi_interface_probe) { ->(_timeout_in_secs) { 'en0' } }
    let(:helper_client) { double('helper_client') }
    let(:command_runner) { double('command_runner') }
    let(:system_profiler_wifi_data) { system_profiler_wifi_payload(current_network_name: 'ProfilerNet') }
    let(:system_profiler_wifi_data_reader) { ->(_timeout_in_secs) { system_profiler_wifi_data } }

    it 'does not predefine the macOS OS detector when required before selection/mac' do
      code = <<~RUBY
        require 'wifi_wand/platforms/mac/status_queries'
        require 'wifi_wand/platforms/selection/mac'

        puts WifiWand::Platforms::Selection::Mac.superclass
        RUBY
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', '-e', code)

      expect(status).to be_success, stderr
      expect(stdout).to eq("WifiWand::Platforms::Selection::Base\n")
    end

    subject(:status_queries) do
      described_class.new(
        helper_client_provider:                 -> { helper_client },
        command_runner:                         command_runner,
        system_profiler_wifi_data_reader:       ->(timeout_in_secs: nil) {
          system_profiler_wifi_data_reader.call(timeout_in_secs)
        },
        system_profiler_wifi_data_cache_runner: ->(&block) { block.call },
        wifi_interface_cache_reader:            -> { wifi_interface_store[:value] },
        wifi_interface_cache_writer:            ->(iface) { wifi_interface_store[:value] = iface },
        wifi_interface_probe:                   ->(timeout_in_secs: nil) {
          wifi_interface_probe.call(timeout_in_secs)
        },
        system_network_info_provider:           -> { system_network_info },
        status_deadline_factory:                ->(timeout_in_secs) {
          timeout_in_secs ? monotonic_now + timeout_in_secs : nil
        },
        status_timeout_calculator:              ->(deadline) {
          deadline ? [deadline - monotonic_now, 0].max : nil
        }
      )
    end


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

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def expect_wifi_power_lookup(on:)
      expect(system_network_info).to receive(:wifi_on?)
        .with(iface: 'en0', timeout_in_secs: status_timeout)
        .and_return(on)
    end

    describe '#status_network_identity' do
      it 'returns a helper SSID inside the bounded status budget' do
        expect_wifi_power_lookup(on: true)
        expect(helper_client).to receive(:connected_network_name)
          .with(timeout_seconds: status_timeout)
          .and_return(helper_result(payload: 'HelperNet'))

        expect(status_queries.status_network_identity(timeout_in_secs: 0.5)).to eq(
          connected:    true,
          network_name: 'HelperNet'
        )
      end

      it 'returns disconnected when Wi-Fi power is off' do
        expect_wifi_power_lookup(on: false)
        expect(helper_client).not_to receive(:connected_network_name)

        expect(status_queries.status_network_identity(timeout_in_secs: 0.5)).to eq(
          connected:    false,
          network_name: nil
        )
      end

      it 'returns disconnected when the helper explicitly reports no connection' do
        expect_wifi_power_lookup(on: true)
        expect(helper_client).to receive(:connected_network_name)
          .with(timeout_seconds: status_timeout)
          .and_return(helper_result(status: :not_connected))
        expect(system_profiler_wifi_data_reader).not_to receive(:call)

        expect(status_queries.status_network_identity(timeout_in_secs: 0.5)).to eq(
          connected:    false,
          network_name: nil
        )
      end

      it 'falls through a timed-out fast network name lookup to bounded system_profiler WiFi data' do
        timeout_error = WifiWand::CommandTimeoutError.new(command: 'networksetup', timeout_in_secs: 0.1)

        expect_wifi_power_lookup(on: true)
        expect(helper_client).to receive(:connected_network_name)
          .with(timeout_seconds: status_timeout)
          .and_return(helper_result)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: status_timeout)
          .and_raise(timeout_error)

        expect(status_queries.status_network_identity(timeout_in_secs: 0.5)).to eq(
          connected:    true,
          network_name: 'ProfilerNet'
        )
      end

      it 'falls through a networksetup placeholder SSID to bounded system_profiler WiFi data' do
        expect_wifi_power_lookup(on: true)
        expect(helper_client).to receive(:connected_network_name)
          .with(timeout_seconds: status_timeout)
          .and_return(helper_result)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: status_timeout)
          .and_return(command_result(stdout: "Current Wi-Fi Network: <redacted>\n"))

        expect(status_queries.status_network_identity(timeout_in_secs: 0.5)).to eq(
          connected:    true,
          network_name: 'ProfilerNet'
        )
      end

      it 'preserves timeout errors from bounded system_profiler WiFi data' do
        timeout_error = WifiWand::CommandTimeoutError.new(
          command:         'system_profiler',
          timeout_in_secs: 0.1
        )
        allow(system_profiler_wifi_data_reader).to receive(:call) do
          raise timeout_error
        end

        expect_wifi_power_lookup(on: true)
        expect(helper_client).to receive(:connected_network_name)
          .with(timeout_seconds: status_timeout)
          .and_return(helper_result)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: status_timeout)
          .and_return(command_result(stdout: ''))

        expect { status_queries.status_network_identity(timeout_in_secs: 0.5) }
          .to raise_error(WifiWand::CommandTimeoutError)
      end

      it 'returns disconnected when status interface detection is unavailable' do
        wifi_interface_store[:value] = nil

        expect(wifi_interface_probe).to receive(:call)
          .with(status_timeout)
          .and_return(nil)
        expect(command_runner).not_to receive(:call)
        expect(helper_client).not_to receive(:connected_network_name)

        expect(status_queries.status_network_identity(timeout_in_secs: 0.5)).to eq(
          connected:    false,
          network_name: nil
        )
      end

      it 'does not cache a blank status interface probe result' do
        wifi_interface_store[:value] = nil

        expect(wifi_interface_probe).to receive(:call)
          .with(status_timeout)
          .and_return('')
        expect(command_runner).not_to receive(:call)
        expect(helper_client).not_to receive(:connected_network_name)

        expect(status_queries.status_network_identity(timeout_in_secs: 0.5)).to eq(
          connected:    false,
          network_name: nil
        )
        expect(wifi_interface_store[:value]).to be_nil
      end

      it 'preserves timeout errors while collecting association evidence' do
        no_current_network = system_profiler_wifi_payload(current_network_name: :missing)
        timeout_error = WifiWand::CommandTimeoutError.new(command: 'ifconfig', timeout_in_secs: 0.1)
        allow(system_profiler_wifi_data_reader).to receive(:call).and_return(no_current_network)

        expect_wifi_power_lookup(on: true)
        expect(helper_client).to receive(:connected_network_name)
          .with(timeout_seconds: status_timeout)
          .and_return(helper_result)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: status_timeout)
          .and_return(command_result(stdout: ''))
        expect(system_network_info).to receive(:default_interface)
          .with(timeout_in_secs: status_timeout)
          .and_return('en1')
        expect(system_network_info).to receive(:ipv4_addresses)
          .with(iface: 'en0', timeout_in_secs: status_timeout)
          .and_raise(timeout_error)

        expect { status_queries.status_network_identity(timeout_in_secs: 0.5) }
          .to raise_error(WifiWand::CommandTimeoutError)
      end

      it 'returns disconnected when association and IP data are unavailable' do
        no_current_network = system_profiler_wifi_payload(current_network_name: :missing)
        allow(system_profiler_wifi_data_reader).to receive(:call).and_return(no_current_network)

        expect_wifi_power_lookup(on: true)
        expect(helper_client).to receive(:connected_network_name)
          .with(timeout_seconds: status_timeout)
          .and_return(helper_result)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: status_timeout)
          .and_return(command_result(stdout: ''))
        expect(system_network_info).to receive(:default_interface)
          .with(timeout_in_secs: status_timeout)
          .and_return('en1')
        expect(system_network_info).to receive(:ipv4_addresses)
          .with(iface: 'en0', timeout_in_secs: status_timeout)
          .and_return([])
        expect(system_network_info).to receive(:ipv6_addresses)
          .with(iface: 'en0', timeout_in_secs: status_timeout)
          .and_return([])

        expect(status_queries.status_network_identity(timeout_in_secs: 0.5)).to eq(
          connected:    false,
          network_name: nil
        )
      end

      it 'returns associated-without-SSID when IP evidence remains without a default route match' do
        no_current_network = system_profiler_wifi_payload(current_network_name: :missing)
        allow(system_profiler_wifi_data_reader).to receive(:call).and_return(no_current_network)

        expect_wifi_power_lookup(on: true)
        expect(helper_client).to receive(:connected_network_name)
          .with(timeout_seconds: status_timeout)
          .and_return(helper_result)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: status_timeout)
          .and_return(command_result(stdout: ''))
        expect(system_network_info).to receive(:default_interface)
          .with(timeout_in_secs: status_timeout)
          .and_return('en1')
        expect(system_network_info).to receive(:ipv4_addresses)
          .with(iface: 'en0', timeout_in_secs: status_timeout)
          .and_return(['192.168.1.44'])

        expect(status_queries.status_network_identity(timeout_in_secs: 0.5)).to eq(
          connected:    true,
          network_name: nil
        )
      end

      it 'returns associated-without-SSID when only IPv6 evidence remains' do
        no_current_network = system_profiler_wifi_payload(current_network_name: :missing)
        allow(system_profiler_wifi_data_reader).to receive(:call).and_return(no_current_network)

        expect_wifi_power_lookup(on: true)
        expect(helper_client).to receive(:connected_network_name)
          .with(timeout_seconds: status_timeout)
          .and_return(helper_result)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: status_timeout)
          .and_return(command_result(stdout: ''))
        expect(system_network_info).to receive(:default_interface)
          .with(timeout_in_secs: status_timeout)
          .and_return('en1')
        expect(system_network_info).to receive(:ipv4_addresses)
          .with(iface: 'en0', timeout_in_secs: status_timeout)
          .and_return([])
        expect(system_network_info).to receive(:ipv6_addresses)
          .with(iface: 'en0', timeout_in_secs: status_timeout)
          .and_return(['2001:db8::44'])

        expect(status_queries.status_network_identity(timeout_in_secs: 0.5)).to eq(
          connected:    true,
          network_name: nil
        )
      end

      it 'does not treat link-local-only IPv6 evidence as associated-without-SSID' do
        no_current_network = system_profiler_wifi_payload(current_network_name: :missing)
        allow(system_profiler_wifi_data_reader).to receive(:call).and_return(no_current_network)

        expect_wifi_power_lookup(on: true)
        expect(helper_client).to receive(:connected_network_name)
          .with(timeout_seconds: status_timeout)
          .and_return(helper_result)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-getairportnetwork', 'en0'], timeout_in_secs: status_timeout)
          .and_return(command_result(stdout: ''))
        expect(system_network_info).to receive(:default_interface)
          .with(timeout_in_secs: status_timeout)
          .and_return('en1')
        expect(system_network_info).to receive(:ipv4_addresses)
          .with(iface: 'en0', timeout_in_secs: status_timeout)
          .and_return([])
        expect(system_network_info).to receive(:ipv6_addresses)
          .with(iface: 'en0', timeout_in_secs: status_timeout)
          .and_return(['fe80::1'])

        expect(status_queries.status_network_identity(timeout_in_secs: 0.5)).to eq(
          connected:    false,
          network_name: nil
        )
      end
    end

    describe '#status_wifi_on?' do
      it 'detects Wi-Fi power using the bounded status interface lookup' do
        wifi_interface_store[:value] = nil

        expect(wifi_interface_probe).to receive(:call)
          .with(status_timeout)
          .and_return('en0')
        expect_wifi_power_lookup(on: true)

        expect(status_queries.status_wifi_on?(timeout_in_secs: 0.5)).to be(true)
        expect(wifi_interface_store[:value]).to eq('en0')
      end
    end

    describe '#status_ipv4_addresses' do
      it 'returns an empty array when status interface detection is unavailable' do
        wifi_interface_store[:value] = nil
        deadline = monotonic_now + 0.5

        expect(wifi_interface_probe).to receive(:call)
          .with(status_timeout)
          .and_return('')
        expect(system_network_info).not_to receive(:ipv4_addresses)

        expect(status_queries.send(:status_ipv4_addresses, deadline)).to eq([])
      end
    end

    describe '#status_ipv6_addresses' do
      it 'returns an empty array when status interface detection is unavailable' do
        wifi_interface_store[:value] = nil
        deadline = monotonic_now + 0.5

        expect(wifi_interface_probe).to receive(:call)
          .with(status_timeout)
          .and_return('')
        expect(system_network_info).not_to receive(:ipv6_addresses)

        expect(status_queries.send(:status_ipv6_addresses, deadline)).to eq([])
      end

      it 'delegates to system network info when a status interface is available' do
        deadline = monotonic_now + 0.5

        expect(system_network_info).to receive(:ipv6_addresses)
          .with(iface: 'en0', timeout_in_secs: status_timeout)
          .and_return(['2001:db8::44'])

        expect(status_queries.send(:status_ipv6_addresses, deadline)).to eq(['2001:db8::44'])
      end
    end
  end
end
