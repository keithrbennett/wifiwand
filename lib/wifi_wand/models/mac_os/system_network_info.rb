# frozen_string_literal: true

require_relative '../../services/command_executor'

module WifiWand
  class MacOsSystemNetworkInfo
    def initialize(command_runner:, wifi_interface_proc:)
      @command_runner = command_runner
      @wifi_interface_proc = wifi_interface_proc
    end

    def ip_address(iface: nil, timeout_in_secs: nil)
      iface ||= @wifi_interface_proc.call
      options = {}
      options[:timeout_in_secs] = timeout_in_secs if timeout_in_secs

      ip_address = @command_runner.call(['ipconfig', 'getifaddr', iface], **options).stdout.chomp
      ip_address.empty? ? nil : ip_address
    rescue WifiWand::CommandExecutor::OsCommandError => e
      raise unless e.exitstatus == 1

      nil
    end

    def mac_address
      iface = @wifi_interface_proc.call
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
  end
end
