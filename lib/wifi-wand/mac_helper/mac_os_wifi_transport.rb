# frozen_string_literal: true

require_relative '../errors'
require_relative '../services/command_executor'

module WifiWand
  class MacOsWifiTransport
    CONNECTION_FAILURE_PATTERNS = [
      /Failed to join network/i,
      /Error:\s*-3900/,
      /Could not connect/i,
      /Could not find network/i,
    ].freeze

    AUTHENTICATION_FAILURE_PATTERNS = [
      /invalid password/i,
      /incorrect password/i,
      /authentication (?:failed|timeout|timed out)/i,
      /802\.1x authentication failed/i,
      /password required/i,
    ].freeze

    SUDO_IFCONFIG_TIMEOUT_SECONDS = 5

    def initialize(swift_runtime:, command_runner:, wifi_interface_proc:, out_stream_proc:, verbose_proc:)
      @swift_runtime = swift_runtime
      @command_runner = command_runner
      @wifi_interface_proc = wifi_interface_proc
      @out_stream_proc = out_stream_proc
      @verbose_proc = verbose_proc
    end

    def connect(network_name, password = nil)
      if swift_runtime.swift_and_corewlan_present?
        begin
          swift_runtime.connect(network_name, password)
          return
        rescue WifiWand::CommandExecutor::OsCommandError => e
          if swift_runtime.fallback_connect_error?(e.text)
            log_fallback(
              "Swift/CoreWLAN failed (#{e.text.strip}). Trying networksetup fallback..."
            )
          else
            raise
          end
        rescue => e
          log_fallback(
            "Swift/CoreWLAN failed: #{e.message}. Trying networksetup fallback..."
          )
        end
      end

      connect_using_networksetup(network_name, password)
    end

    def disconnect
      if swift_runtime.swift_and_corewlan_present?
        begin
          swift_runtime.disconnect
          return
        rescue => e
          log_fallback(
            "Swift/CoreWLAN disconnect failed: #{e.message}. Falling back to ifconfig..."
          )
        end
      elsif verbose?
        out_stream.puts 'Swift/CoreWLAN not available. Using ifconfig...'
      end

      disconnect_using_ifconfig
    end

    private attr_reader :swift_runtime

    private def connect_using_networksetup(network_name, password = nil)
      iface = wifi_interface
      args = ['networksetup', '-setairportnetwork', iface, network_name]
      args << password if password
      result = run_command_using_args(args)
      output_text = result.combined_output

      # networksetup returns exit code 0 even on failure, so check output text.
      check_connection_result(network_name, output_text)
    end

    private def check_connection_result(network_name, output_text)
      return unless connection_failed?(output_text)

      if authentication_failed?(output_text)
        reason = extract_auth_failure_reason(output_text)
        raise(WifiWand::NetworkAuthenticationError.new(network_name: network_name, reason: reason))
      end

      raise(WifiWand::CommandExecutor::OsCommandError.new(
        exitstatus: 1,
        command:    'networksetup',
        text:       output_text.strip
      ))
    end

    private def disconnect_using_ifconfig
      iface = wifi_interface
      sudo_result = run_command_using_args(
        ['sudo', 'ifconfig', iface, 'disassociate'],
        false,
        timeout_in_secs: SUDO_IFCONFIG_TIMEOUT_SECONDS
      )
      return nil if sudo_result.success?

      plain_result = run_command_using_args(['ifconfig', iface, 'disassociate'], false)
      return nil if plain_result.success?

      raise(WifiWand::NetworkDisconnectionError.new(
        network_name: nil,
        reason:       disconnect_failure_reason(sudo_result, plain_result)
      ))
    end

    private def extract_auth_failure_reason(output_text)
      return '' if output_text.nil?

      lines = output_text.lines.map(&:strip).reject(&:empty?)
      filtered = lines.grep_v(/Failed to join network/i)
      reason = filtered.join(' ')
      reason.empty? ? output_text.strip : reason
    end

    private def connection_failed?(output_text)
      CONNECTION_FAILURE_PATTERNS.any? { |pattern| output_text.match?(pattern) }
    end

    private def authentication_failed?(output_text)
      AUTHENTICATION_FAILURE_PATTERNS.any? { |pattern| output_text.match?(pattern) }
    end

    private def disconnect_failure_reason(*results)
      messages = results.compact.reject(&:success?).map do |result|
        message = "#{result.command} exited with status #{result.exitstatus}"
        details = result.combined_output.to_s.strip
        details.empty? ? message : "#{message}: #{details}"
      end
      messages.join('; ')
    end

    private def run_command_using_args(*, **)
      @command_runner.call(*, **)
    end

    private def log_fallback(message)
      out_stream.puts message if verbose?
    end

    private def wifi_interface = @wifi_interface_proc.call

    private def out_stream = @out_stream_proc.call

    private def verbose? = @verbose_proc.call
  end
end
