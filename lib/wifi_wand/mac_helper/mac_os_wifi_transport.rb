# frozen_string_literal: true

require_relative '../errors'
require_relative '../services/command_executor'
require_relative '../string_predicates'

module WifiWand
  # Orchestrates the direct Swift-source runtime path for macOS
  # connect/disconnect mutations. Query/read operations that need a stable app
  # identity stay on the compiled helper path via MacOsHelperClient.
  class MacOsWifiTransport
    include StringPredicates

    CONNECTION_FAILURE_PATTERNS = [
      /Failed to join network/i,
      /Error:\s*-3900/,
      /Could not connect/i,
      /Could not find network/i,
    ].freeze

    AUTHENTICATION_FAILURE_PATTERNS = [
      /invalid password/i,
      /incorrect password/i,
      /password.*incorrect/i,
      /authentication (?:failed|timeout|timed out)/i,
      /802\.1x authentication failed/i,
      /password required/i,
    ].freeze

    SWIFT_CONNECTION_FAILURE_PATTERNS = [
      /connection timeout/i,
      /connection attempt timed out/i,
      /out of range/i,
      /unreachable/i,
    ].freeze

    FAILURE_REASON_HEADER_PATTERNS = [
      /Failed to join network/i,
      /\AError:\s*Failed to join\b/i,
    ].freeze

    SUDO_IFCONFIG_TIMEOUT_SECONDS = 5
    # StandardError excludes process-control and VM-level exceptions like Interrupt, SystemExit, and NoMemoryError.
    UNEXPECTED_SWIFT_ERROR = StandardError

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
          handle_swift_connect_command_error(network_name, e)
        rescue WifiWand::CommandTimeoutError, WifiWand::CommandNotFoundError,
          WifiWand::CommandSpawnError => e
          log_fallback(
            "Swift/CoreWLAN failed: #{e.message}. Trying networksetup fallback..."
          )
        rescue UNEXPECTED_SWIFT_ERROR => e
          log_unexpected_swift_error('connect', e)
          raise
        end
      end

      connect_using_networksetup(network_name, password)
    end

    def disconnect
      if swift_runtime.swift_and_corewlan_present?
        begin
          swift_runtime.disconnect
          return
        rescue WifiWand::CommandExecutor::OsCommandError, WifiWand::CommandTimeoutError,
          WifiWand::CommandNotFoundError, WifiWand::CommandSpawnError => e
          log_fallback(
            "Swift/CoreWLAN disconnect failed: #{e.message}. Falling back to ifconfig..."
          )
        rescue UNEXPECTED_SWIFT_ERROR => e
          log_unexpected_swift_error('disconnect', e)
          raise
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
      result = run_networksetup_connect_command(network_name, args)
      output_text = result.combined_output

      # networksetup returns exit code 0 even on failure, so check output text.
      check_connection_result(network_name, output_text)
    end

    private def run_networksetup_connect_command(network_name, args)
      run_command(args)
    rescue WifiWand::CommandExecutor::OsCommandError => e
      raise_networksetup_connect_error(network_name, e.text)
    end

    private def check_connection_result(network_name, output_text)
      return unless connection_failed?(output_text)

      raise_networksetup_connect_error(network_name, output_text)
    end

    private def raise_networksetup_connect_error(network_name, output_text)
      if authentication_failed?(output_text)
        reason = extract_failure_reason(output_text)
        raise(WifiWand::NetworkAuthenticationError.new(network_name: network_name, reason: reason))
      end

      raise(WifiWand::NetworkConnectionError.new(
        network_name: network_name,
        reason:       extract_failure_reason(output_text),
        source:       :networksetup
      ))
    end

    private def handle_swift_connect_command_error(network_name, error)
      classified_error = swift_authentication_domain_error(network_name, error.text)
      raise classified_error if classified_error

      if swift_runtime.fallback_connect_error?(error.text)
        log_fallback(
          "Swift/CoreWLAN failed (#{error.text.to_s.strip}). Trying networksetup fallback..."
        )
        return
      end

      classified_error = swift_connection_domain_error(network_name, error.text)
      raise classified_error if classified_error

      raise error
    end

    private def swift_authentication_domain_error(network_name, output_text)
      return unless authentication_failed?(output_text)

      WifiWand::NetworkAuthenticationError.new(
        network_name: network_name,
        reason:       extract_failure_reason(output_text)
      )
    end

    private def swift_connection_domain_error(network_name, output_text)
      return unless swift_connection_failed?(output_text)

      WifiWand::NetworkConnectionError.new(
        network_name: network_name,
        reason:       extract_failure_reason(output_text),
        source:       :swift
      )
    end

    private def disconnect_using_ifconfig
      iface = wifi_interface
      sudo_result = run_command(
        ['sudo', 'ifconfig', iface, 'disassociate'],
        raise_on_error:  false,
        timeout_in_secs: SUDO_IFCONFIG_TIMEOUT_SECONDS
      )
      return nil if sudo_result.success?

      plain_result = run_command(['ifconfig', iface, 'disassociate'], raise_on_error: false)
      return nil if plain_result.success?

      raise(WifiWand::NetworkDisconnectionError.new(
        network_name: nil,
        reason:       disconnect_failure_reason(sudo_result, plain_result)
      ))
    rescue WifiWand::CommandExecutor::OsCommandError, WifiWand::CommandTimeoutError,
      WifiWand::CommandNotFoundError, WifiWand::CommandSpawnError => e
      raise(WifiWand::NetworkDisconnectionError.new(
        network_name: nil,
        reason:       command_error_detail(e)
      ))
    end

    private def extract_failure_reason(output_text)
      return '' if output_text.nil?

      lines = output_text.lines.map(&:strip).reject(&:empty?)
      filtered = lines.reject { |line| failure_reason_header?(line) }
      reason = filtered.join(' ')
      reason.empty? ? output_text.strip : reason
    end

    private def failure_reason_header?(line)
      FAILURE_REASON_HEADER_PATTERNS.any? { |pattern| line.match?(pattern) }
    end

    private def connection_failed?(output_text)
      CONNECTION_FAILURE_PATTERNS.any? { |pattern| output_text.to_s.match?(pattern) }
    end

    private def authentication_failed?(output_text)
      AUTHENTICATION_FAILURE_PATTERNS.any? { |pattern| output_text.to_s.match?(pattern) }
    end

    private def swift_connection_failed?(output_text)
      SWIFT_CONNECTION_FAILURE_PATTERNS.any? { |pattern| output_text.to_s.match?(pattern) }
    end

    private def disconnect_failure_reason(*results)
      messages = results.compact.reject(&:success?).map do |result|
        message = "#{result.command} exited with status #{result.exitstatus}"
        details = result.combined_output.to_s.strip
        details.empty? ? message : "#{message}: #{details}"
      end
      messages.join('; ')
    end

    private def command_error_detail(error)
      detail = error.display_message if error.respond_to?(:display_message)
      detail = error.message if string_nil_or_empty?(detail)
      detail.to_s
    end

    private def run_command(*, **)
      @command_runner.call(*, **)
    end

    private def log_fallback(message)
      out_stream.puts message if verbose?
    end

    private def log_unexpected_swift_error(operation, error)
      return unless verbose?

      out_stream.puts "Unexpected Swift/CoreWLAN #{operation} error: #{error.class}: #{error.message}"
    end

    private def wifi_interface = @wifi_interface_proc.call

    private def out_stream = @out_stream_proc.call

    private def verbose? = @verbose_proc.call
  end
end
