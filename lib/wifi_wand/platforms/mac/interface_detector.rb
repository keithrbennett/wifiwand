# frozen_string_literal: true

require 'json'

require_relative 'system_profiler_wifi_data_provider'
require_relative '../../errors'
require_relative '../../services/command_executor'
require_relative '../../string_predicates'

module WifiWand
  module Platforms
    module Mac
      class InterfaceDetector
        include StringPredicates

        WIFI_PORT_PATTERNS = [
          /Wi[-\s]?Fi/i,
          /Air[-\s]?Port/i,
          /Wireless/i,
          /WLAN/i,
        ].freeze

        SYSTEM_PROFILER_NETWORK_ARGS = %w[system_profiler -json SPNetworkDataType].freeze
        SYSTEM_PROFILER_TIMEOUT_SECONDS = SystemProfilerWifiDataProvider::SYSTEM_PROFILER_TIMEOUT_SECONDS

        DetectionResult = Struct.new(:interface, :service_name, keyword_init: true)

        def initialize(command_runner:)
          @command_runner = command_runner
        end

        def fetch_hardware_ports(timeout_in_secs: nil)
          output = command_runner.call(
            %w[networksetup -listallhardwareports],
            timeout_in_secs: timeout_in_secs
          ).stdout

          parse_hardware_ports(output)
        end

        def parse_hardware_ports(output)
          ports = []
          current = {}

          output.each_line do |line|
            stripped = line.strip
            next if stripped.empty?

            if (match = stripped.match(/^Hardware Port:\s*(.+)$/))
              ports << current if current[:device]
              current = { name: match[1] }
            elsif (match = stripped.match(/^Device:\s*(.+)$/))
              current[:device] = match[1]
            elsif (match = stripped.match(/^Ethernet Address:\s*(.+)$/))
              current[:ethernet_address] = match[1]
            end
          end

          ports << current if current[:device]
          ports
        end

        def wifi_port_from_ports(ports)
          ports.find do |port|
            name = port[:name].to_s
            next false if name.empty?

            WIFI_PORT_PATTERNS.any? { |pattern| pattern.match?(name) }
          end
        end

        def wifi_service_name_from_ports(ports, known_interface: nil, fallback_service_name: 'Wi-Fi')
          wifi_port = wifi_port_from_ports(ports)
          return wifi_port[:name] if wifi_port && wifi_port[:name] && !wifi_port[:name].empty?

          if known_interface && !known_interface.empty?
            match = ports.find do |port|
              port[:device] == known_interface && port[:name] && !port[:name].empty?
            end
            return match[:name] if match
          end

          fallback_service_name
        end

        def wifi_service_name(known_interface: nil, timeout_in_secs: nil)
          wifi_service_name_from_ports(
            fetch_hardware_ports(timeout_in_secs: timeout_in_secs),
            known_interface: known_interface
          )
        end

        def detected_wifi_service_name(known_interface: nil, timeout_in_secs: nil)
          wifi_service_name_from_ports(
            fetch_hardware_ports(timeout_in_secs: timeout_in_secs),
            known_interface:       known_interface,
            fallback_service_name: nil
          )
        end

        def detect_using_networksetup(timeout_in_secs: nil, known_interface: nil)
          result = wifi_interface_using_networksetup(
            timeout_in_secs: timeout_in_secs,
            known_interface: known_interface
          )
          raise WifiInterfaceError if string_nil_or_empty?(result.interface)

          result
        end

        def probe(timeout_in_secs: nil, known_interface: nil, known_service_name: nil)
          deadline = status_deadline(timeout_in_secs)
          networksetup_result = nil

          begin
            networksetup_result = wifi_interface_using_networksetup(
              timeout_in_secs: status_timeout_for(deadline),
              known_interface: known_interface
            )
            if networksetup_result.interface && !networksetup_result.interface.empty?
              return networksetup_result
            end
          rescue WifiWand::Error
            # Fall through to system_profiler fallback.
          end

          service_name = networksetup_result&.service_name || known_service_name
          interface = networksetup_result&.interface || known_interface
          wifi_interface_using_system_profiler(
            timeout_in_secs:    status_timeout_for(deadline),
            known_interface:    interface,
            known_service_name: service_name
          )
        end

        def wifi_interface_using_networksetup(timeout_in_secs: nil, known_interface: nil)
          ports = fetch_hardware_ports(timeout_in_secs: timeout_in_secs)
          service_name = wifi_service_name_from_ports(ports, known_interface: known_interface)

          wifi_port = ports.find do |port|
            port[:name] == service_name && port[:device] && !port[:device].empty?
          end
          wifi_port ||= wifi_port_from_ports(ports)

          iface = wifi_port && wifi_port[:device]
          DetectionResult.new(interface: present_string(iface), service_name: present_string(service_name))
        end

        def wifi_interface_using_system_profiler(timeout_in_secs: nil, known_interface: nil,
          known_service_name: nil)
          json_text = command_runner.call(
            SYSTEM_PROFILER_NETWORK_ARGS,
            raise_on_error:  true,
            timeout_in_secs: timeout_in_secs || SYSTEM_PROFILER_TIMEOUT_SECONDS
          ).stdout
          return DetectionResult.new if string_nil_or_blank?(json_text)

          net_data = JSON.parse(json_text)
          nets = net_data['SPNetworkDataType']
          return DetectionResult.new if nets.nil? || nets.empty?

          detect_wifi_interface_from_profiler_networks(
            nets,
            known_interface:    known_interface,
            known_service_name: known_service_name
          )
        end

        def detect_wifi_interface_from_profiler_networks(nets, known_interface: nil,
          known_service_name: nil)
          wifi = if known_service_name && !known_service_name.empty?
            nets.find { |net| net['_name'] == known_service_name }
          end

          wifi ||= if known_interface && !known_interface.empty?
            nets.find { |net| net['interface'] == known_interface }
          end

          wifi ||= nets.find do |net|
            name = net['_name'].to_s
            WIFI_PORT_PATTERNS.any? { |pattern| pattern.match?(name) }
          end

          DetectionResult.new(
            interface:    present_string(wifi && wifi['interface']),
            service_name: present_string(wifi && wifi['_name'])
          )
        end

        def is_wifi_interface?(interface)
          command_runner.call(['networksetup', '-listpreferredwirelessnetworks', interface])
          true
        rescue WifiWand::CommandExecutor::OsCommandError => e
          if e.exitstatus == 10
            false
          else
            raise
          end
        end

        private attr_reader :command_runner

        private def status_deadline(timeout_in_secs)
          monotonic_now + timeout_in_secs if timeout_in_secs
        end

        private def status_timeout_for(deadline)
          return nil unless deadline

          [deadline - monotonic_now, 0].max
        end

        private def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        private def present_string(value)
          value if value && !value.empty?
        end
      end
    end
  end
end
