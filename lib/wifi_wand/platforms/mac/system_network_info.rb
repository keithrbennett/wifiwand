# frozen_string_literal: true

require_relative 'helper/bundle'
require_relative '../../errors'
require_relative '../../services/command_executor'
require_relative '../../services/ip_address_extractor'

module WifiWand
  module Platforms
    module Mac
      class SystemNetworkInfo
        def initialize(command_runner:, wifi_interface_provider:, out_stream_provider: nil,
          err_stream_provider: nil, verbosity_provider: nil)
          @command_runner = command_runner
          @wifi_interface_provider = wifi_interface_provider
          @out_stream_provider = out_stream_provider
          @err_stream_provider = err_stream_provider
          @verbosity_provider = verbosity_provider
        end

        def ipv4_addresses(iface: nil, timeout_in_secs: nil)
          interface_addresses(iface: iface, timeout_in_secs: timeout_in_secs, line_type: 'inet',
            family: :ipv4)
        end

        def ipv6_addresses(iface: nil, timeout_in_secs: nil)
          interface_addresses(iface: iface, timeout_in_secs: timeout_in_secs, line_type: 'inet6',
            family: :ipv6)
        end

        private def interface_addresses(line_type:, family:, iface: nil, timeout_in_secs: nil)
          iface ||= @wifi_interface_provider.call
          options = {}
          options[:timeout_in_secs] = timeout_in_secs if timeout_in_secs

          output = @command_runner.call(['ifconfig', iface], **options).stdout
          IPAddressExtractor.addresses(output, line_type: line_type, family: family)
        rescue WifiWand::CommandExecutor::OsCommandError => e
          raise unless e.exitstatus == 1

          []
        end

        def wifi_on?(iface: nil, timeout_in_secs: nil)
          iface ||= @wifi_interface_provider.call
          options = {}
          options[:timeout_in_secs] = timeout_in_secs if timeout_in_secs

          output = @command_runner.call(['networksetup', '-getairportpower', iface], **options).stdout
          output.chomp.match?(/\): On$/)
        end

        def mac_address
          iface = @wifi_interface_provider.call
          output = @command_runner.call(['ifconfig', iface]).stdout
          ether_line = output.split("\n").find { |line| line.include?('ether') }
          return nil unless ether_line

          tokens = ether_line.split
          ether_index = tokens.index('ether')
          ether_index ? tokens[ether_index + 1] : nil
        end

        def default_interface(timeout_in_secs: nil)
          options = { raise_on_error: false }
          options[:timeout_in_secs] = timeout_in_secs if timeout_in_secs

          output = @command_runner.call(%w[route -n get default], **options).stdout
          return nil if output.empty?

          interface_line = output.split("\n").find { |line| line.include?('interface:') }
          return nil unless interface_line

          default_iface = interface_line.split(':', 2).last.strip
          default_iface.empty? ? nil : default_iface
        rescue WifiWand::CommandExecutor::OsCommandError
          nil
        end

        def open_resource(resource_url)
          @command_runner.call(['open', resource_url])
        end

        def detect_macos_version(timeout_in_secs: nil)
          options = {}
          options[:timeout_in_secs] = timeout_in_secs if timeout_in_secs

          output = @command_runner.call(%w[sw_vers -productVersion], **options).stdout
          Helper::Bundle.normalize_detected_macos_version(output)
        rescue WifiWand::CommandExecutor::OsCommandError, WifiWand::CommandTimeoutError,
          WifiWand::CommandNotFoundError, WifiWand::CommandSpawnError => e
          err_stream.puts "Could not detect macOS version: #{e.message}." if verbose?
          nil
        end

        private def verbose? = @verbosity_provider&.call

        private def out_stream = @out_stream_provider ? @out_stream_provider.call : $stdout

        private def err_stream = @err_stream_provider ? @err_stream_provider.call : $stderr
      end
    end
  end
end
