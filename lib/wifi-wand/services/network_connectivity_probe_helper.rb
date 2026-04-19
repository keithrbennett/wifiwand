# frozen_string_literal: true

require 'json'
require_relative 'network_connectivity_tester'

module WifiWand
  module NetworkConnectivityProbeHelper
    def self.parse_argv(argv)
      mode, *args = argv

      case mode
      when 'tcp', 'fast_tcp'
        host, port_arg = args
        raise ArgumentError, 'host argument is required' if host.to_s.strip.empty?
        raise ArgumentError, 'port argument is required' if port_arg.to_s.strip.empty?

        { mode: mode.to_sym, target: { host: host, port: Integer(port_arg) } }
      when 'dns'
        domain = args.first
        raise ArgumentError, 'domain argument is required' if domain.to_s.strip.empty?

        { mode: :dns, target: domain }
      else
        raise ArgumentError, 'mode must be tcp, fast_tcp, or dns'
      end
    end

    def self.run(argv, output: $stdout, tester: nil)
      probe = parse_argv(argv)
      tester ||= NetworkConnectivityTester.new(verbose: false, output: $stderr)
      success = run_probe(tester, probe)
      output.print(JSON.generate(success: success))
      output.flush
    rescue => e
      output.print(JSON.generate(success: false, error_class: e.class.to_s, error_message: e.message))
      output.flush
    end

    def self.run_probe(tester, probe)
      tester.run_probe(probe[:mode], probe[:target])
    end
  end
end

WifiWand::NetworkConnectivityProbeHelper.run(ARGV) if $PROGRAM_NAME == __FILE__
