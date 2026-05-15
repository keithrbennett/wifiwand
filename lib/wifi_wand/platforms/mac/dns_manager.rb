# frozen_string_literal: true

require 'ipaddr'

require_relative '../../errors'

module WifiWand
  module Platforms
    module Mac
      class DnsManager
        def initialize(command_runner:, service_name_proc:)
          @command_runner = command_runner
          @service_name_proc = service_name_proc
        end

        def set_nameservers(nameservers) # rubocop:disable Naming/AccessorMethodName
          service_name = @service_name_proc.call

          if nameservers == :clear
            @command_runner.call(['networksetup', '-setdnsservers', service_name, 'empty'])
          else
            bad_addresses = invalid_nameservers(nameservers)
            raise InvalidIPAddressError, bad_addresses unless bad_addresses.empty?

            @command_runner.call(['networksetup', '-setdnsservers', service_name] + nameservers)
          end

          nameservers
        end

        def nameservers_using_scutil
          output = @command_runner.call(%w[scutil --dns]).stdout
          nameserver_lines = output.split("\n").grep(/^\s*nameserver\[/).uniq
          nameserver_lines.map { |line| line.split(' : ').last.strip }
        end

        def nameservers_using_networksetup
          service_name = @service_name_proc.call
          output = @command_runner.call(['networksetup', '-getdnsservers', service_name]).stdout
          if output == "There aren't any DNS Servers set on #{service_name}.\n"
            output = ''
          end
          output.split("\n")
        end

        private def invalid_nameservers(nameservers)
          nameservers.reject do |nameserver|
            IPAddr.new(nameserver)
            true
          rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
            false
          end
        end
      end
    end
  end
end
