# frozen_string_literal: true

require 'json'

module WifiWand
  module MacOsHelperBundle
    HelperQueryResult = Struct.new(
      :payload,
      :location_services_blocked,
      :error_message,
      keyword_init: true
    ) do
      def location_services_blocked? = !!location_services_blocked
    end
  end

  # Talks to the compiled macOS helper app used for permission-sensitive
  # read/query operations such as current-network lookups and network scans.
  # Connect/disconnect mutations still run through MacOsSwiftRuntime.
  class MacOsHelperClient
    attr_reader :last_error_message

    def initialize(out_stream_proc:, verbose_proc:, macos_version_proc:)
      @out_stream_proc = out_stream_proc
      @verbose_proc = verbose_proc
      @macos_version_proc = macos_version_proc
      @location_warning_emitted = false
      @helper_install_verified = false
      @disabled = false
      @last_error_message = nil
    end

    def connected_network_name
      result = execute('current-network')
      ssid = result.payload&.fetch('ssid', nil)
      MacOsHelperBundle::HelperQueryResult.new(
        payload:                   ssid,
        location_services_blocked: result.location_services_blocked,
        error_message:             result.error_message
      )
    end

    def scan_networks
      result = execute('scan-networks')
      networks = result.payload&.fetch('networks', []) || []
      MacOsHelperBundle::HelperQueryResult.new(
        payload:                   networks,
        location_services_blocked: result.location_services_blocked,
        error_message:             result.error_message
      )
    end

    def available?
      return false if helper_disabled?

      version = macos_version
      return false unless version

      support_status = MacOsHelperBundle.helper_support_status_for_macos_version(version)
      return true if support_status.supported?

      if support_status.unknown?
        log_verbose("macOS version '#{version}' does not match expected format")
      end
      false
    end

    def location_services_blocked?
      return false unless @last_error_message

      @last_error_message.downcase.include?('location services')
    end

    private def execute(command)
      @last_error_message = nil
      return MacOsHelperBundle::HelperQueryResult.new unless available?

      ensure_helper_installed
      return MacOsHelperBundle::HelperQueryResult.new if helper_disabled?

      helper_result = execute_helper_command(command)
      return MacOsHelperBundle::HelperQueryResult.new unless helper_result

      stdout = helper_result[:stdout]
      stderr = helper_result[:stderr]
      status = helper_result[:status]
      unless status.success?
        log_verbose("helper exited with status #{status.exitstatus}: #{stderr.strip}")
        return MacOsHelperBundle::HelperQueryResult.new
      end

      payload = parse_json(stdout)
      return MacOsHelperBundle::HelperQueryResult.new unless payload

      if payload['status'] == 'error'
        error_msg = payload['error']
        handle_error(error_msg)
        return MacOsHelperBundle::HelperQueryResult.new(
          location_services_blocked: error_msg&.downcase&.include?('location services'),
          error_message:             error_msg
        )
      end

      MacOsHelperBundle::HelperQueryResult.new(payload: payload)
    rescue Errno::ENOENT => e
      log_verbose("helper executable missing: #{e.message}")
      MacOsHelperBundle::HelperQueryResult.new
    rescue => e
      log_verbose("helper command '#{command}' failed: #{e.message}")
      MacOsHelperBundle::HelperQueryResult.new
    end

    private def execute_helper_command(command)
      WifiWand::MacOsHelperBundle.run_bounded_helper_command(
        helper_executable_path,
        command,
        timeout_seconds: WifiWand::MacOsHelperBundle.helper_command_timeout_seconds(command),
        on_timeout:      ->(timed_out_command, timeout_seconds) do
          log_verbose("helper command '#{timed_out_command}' timed out after #{timeout_seconds}s")
        end
      )
    end

    private def ensure_helper_installed
      return if helper_disabled?
      return if @helper_install_verified

      helper_present = File.executable?(helper_executable_path)
      helper_valid = WifiWand::MacOsHelperBundle.helper_installed_and_valid?
      if helper_valid
        @helper_install_verified = true
        return
      end

      if helper_present
        log_verbose('existing helper install failed validation; attempting reinstall')
      else
        log_verbose('helper not installed; running installer')
      end

      WifiWand::MacOsHelperBundle.ensure_helper_installed(out_stream: verbose? ? out_stream : nil)
      @helper_install_verified = true
    rescue => e
      @helper_install_verified = false
      @disabled = true
      emit_install_failure(e.message, reinstall_required: helper_present)
    end

    private def helper_executable_path = WifiWand::MacOsHelperBundle.installed_executable_path

    private def helper_disabled?
      @disabled || ENV[MacOsHelperBundle::DISABLE_ENV_KEY] == '1'
    end

    private def parse_json(text)
      JSON.parse(text)
    rescue JSON::ParserError => e
      log_verbose("failed to parse helper JSON: #{e.message}")
      nil
    end

    private def handle_error(message)
      return unless message

      @last_error_message = message
      if message.downcase.include?('location services')
        emit_location_warning
      else
        log_verbose("helper error: #{message}")
      end
    end

    private def emit_location_warning
      return if @location_warning_emitted

      stream = out_stream || $stdout
      if stream
        stream.puts('wifiwand helper: Location Services denied. ' \
          'Run `wifi-wand-macos-setup` (or `wifi-wand-macos-setup --reinstall`) ' \
          'to grant location access.')
      end
      @location_warning_emitted = true
    end

    private def emit_install_failure(detail, reinstall_required: false)
      stream = out_stream || $stdout
      if stream
        reinstall_hint = if reinstall_required
          ' Run `wifi-wand-macos-setup --reinstall` to reinstall it.'
        else
          ''
        end
        stream.puts("wifiwand helper: failed to install helper (#{detail}). " \
          "Helper disabled until the next run.#{reinstall_hint}")
      end
    end

    private def log_verbose(message)
      return unless verbose?

      stream = out_stream || $stdout
      stream.puts("wifiwand helper: #{message}") if stream
    end

    private def macos_version = @macos_version_proc&.call

    private def out_stream = @out_stream_proc&.call

    private def verbose? = !!(@verbose_proc && @verbose_proc.call)
  end
end
