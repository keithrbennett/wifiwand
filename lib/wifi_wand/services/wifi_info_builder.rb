# frozen_string_literal: true

require 'socket'
require 'timeout'

require_relative '../connectivity_states'
require_relative '../errors'
require_relative '../network_identity'
require_relative '../runtime_config'
require_relative 'command_executor'
require_relative '../network_error_constants'

module WifiWand
  class WifiInfoBuilder
    attr_reader :model
    private attr_reader :runtime_config, :expected_network_errors, :network_operation_command_errors

    def initialize(model, runtime_config: nil, expected_network_errors: NetworkErrorConstants::EXPECTED_NETWORK_ERRORS,
      network_operation_command_errors: NetworkErrorConstants::NETWORK_OPERATION_COMMAND_ERRORS)
      @model = model
      @runtime_config = runtime_config || RuntimeConfig.new
      @expected_network_errors = expected_network_errors
      @network_operation_command_errors = network_operation_command_errors
    end

    def build
      debug(__method__)
      connectivity = wifi_info_connectivity
      internet_tcp = connectivity.fetch(:internet_tcp)
      dns_working = connectivity.fetch(:dns_working)
      portal_login_required = connectivity.fetch(:portal_login_required)

      connectivity_state = ConnectivityStates.internet_state_from_login_required(
        tcp_working:                   internet_tcp,
        dns_working:                   dns_working,
        captive_portal_login_required: portal_login_required
      )

      network_identity = wifi_info_network_identity

      {
        'wifi_on'                       => model.wifi_on?,
        'internet_tcp_connectivity'     => internet_tcp,
        'dns_working'                   => dns_working,
        'captive_portal_login_required' => portal_login_required,
        'internet_connectivity_state'   => connectivity_state,
        'interface'                     => model.wifi_interface,
        'default_interface'             => begin; model.default_interface; rescue WifiWand::Error; nil; end,
        'connected'                     => network_identity.fetch('connected'),
        'network'                       => network_identity.fetch('network'),
        'bssid'                         => begin; model.bssid; rescue WifiWand::Error; nil; end,
        'signal_quality'                => wifi_info_signal_quality,
        'ssid_identity_available'       => network_identity.fetch('ssid_identity_available'),
        'ssid_identity_status'          => network_identity.fetch('ssid_identity_status'),
        'ssid_identity_warning'         => network_identity.fetch('ssid_identity_warning'),
        'ipv4_addresses'                => wifi_info_ipv4_addresses,
        'ipv6_addresses'                => wifi_info_ipv6_addresses,
        'mac_address'                   => begin; model.mac_address; rescue WifiWand::Error; nil; end,
        'nameservers'                   => begin; model.nameservers; rescue WifiWand::Error; []; end,
        'timestamp'                     => Time.now,
      }
    end

    def successful_available_network_scan(networks)
      {
        'networks'          => Array(networks),
        'scan_status'       => 'ok',
        'scan_source'       => 'os',
        'ssid_data_trusted' => true,
        'warning'           => nil,
      }
    end

    private def verbose? = runtime_config.verbose

    private def debug(method_name)
      return unless verbose?

      runtime_config.err_stream.puts("Entered WifiInfoBuilder##{method_name}")
    end

    private def wifi_info_connectivity
      initial_probe_results = wifi_info_initial_connectivity_probe_results
      internet_tcp = initial_probe_results.fetch(:internet_tcp)
      dns_working = initial_probe_results.fetch(:dns_working)

      {
        internet_tcp:          internet_tcp,
        dns_working:           dns_working,
        portal_login_required: wifi_info_captive_portal_login_required(internet_tcp, dns_working),
      }
    end

    private def wifi_info_initial_connectivity_probe_results
      workers = {}
      result_queue = Queue.new
      workers[:internet_tcp] = wifi_info_probe_worker(result_queue, :internet_tcp) do
        model.internet_tcp_connectivity?
      end
      workers[:dns_working] = wifi_info_probe_worker(result_queue, :dns_working) { model.dns_working? }

      wifi_info_collect_probe_results(result_queue, workers)
    ensure
      workers.each_value(&:join)
    end

    private def wifi_info_probe_worker(result_queue, probe_name)
      Thread.new do
        result_queue << [probe_name, :result, yield]
      rescue *expected_network_errors, WifiWand::Error
        result_queue << [probe_name, :result, false]
      rescue StandardError, ScriptError => e
        result_queue << [probe_name, :error, e]
      end
    end

    private def wifi_info_collect_probe_results(result_queue, workers)
      results = {}

      until results.length == workers.length
        probe_name, status, payload = wifi_info_next_probe_result(result_queue, workers, results)
        raise payload if status == :error

        results[probe_name] = payload
      end

      results
    end

    private def wifi_info_next_probe_result(result_queue, workers, results)
      loop do
        # Use a blocking pop with a timeout. This avoids a tight poll loop and
        # gives JRuby time to make a worker's Queue write visible after the
        # worker has finished, which prevents false "exited without result"
        # errors caused by JRuby's thread/Queue visibility ordering.
        item = result_queue.pop(timeout: 1)
        return item if item

        probe_name, worker = workers.find { |name, thread| !results.key?(name) && !thread.alive? }

        if worker
          worker.value
          raise(WifiWand::Error, "WiFi info probe #{probe_name} exited without reporting a result")
        end
      end
    end

    private def wifi_info_captive_portal_login_required(internet_tcp, dns_working)
      return :unknown unless internet_tcp && dns_working

      model.captive_portal_login_required
    rescue *expected_network_errors, WifiWand::Error
      :unknown
    end

    private def wifi_info_ipv4_addresses
      wifi_info_network_addresses(:ipv4_addresses)
    end

    private def wifi_info_signal_quality
      model.signal_quality&.to_h
    rescue WifiWand::Error
      nil
    end

    private def wifi_info_ipv6_addresses
      wifi_info_network_addresses(:ipv6_addresses)
    end

    private def wifi_info_network_addresses(method_name)
      model.public_send(method_name)
    rescue *network_operation_command_errors
      []
    rescue WifiWand::Error => e
      raise unless wifi_info_network_addresses_unavailable_error?(e)

      []
    end

    private def wifi_info_network_addresses_unavailable_error?(error)
      error.is_a?(WifiWand::WifiOffError) ||
        error.is_a?(WifiWand::WifiInterfaceError) ||
        (error.instance_of?(WifiWand::Error) && error.message.include?('not connected'))
    end

    private def wifi_info_network_identity
      connected = begin; model.connected?; rescue WifiWand::Error; nil; end
      warning = nil
      network_name = begin
        model.connected_network_name
      rescue WifiWand::MacOsRedactionError => e
        warning = e.message
        nil
      rescue WifiWand::Error
        nil
      end

      status = if NetworkIdentity.named?(network_name)
        'available'
      elsif connected == true
        'unavailable'
      elsif connected == false
        'not_connected'
      else
        'unknown'
      end

      {
        'connected'               => connected,
        'network'                 => network_name,
        'ssid_identity_available' => status == 'available',
        'ssid_identity_status'    => status,
        'ssid_identity_warning'   => warning,
      }
    end
  end
end
