# frozen_string_literal: true

require 'json'

module WifiWand
  module MacOsHelperBundle
    # Current-network query states. Ambiguous states preserve nil-payload fallback behavior
    # while allowing future callers to choose a more specific fallback policy.
    HELPER_QUERY_STATUSES = %i[
      success
      connected
      not_connected
      location_services_blocked
      permission_denied
      unavailable
      timeout
      error
      unknown
    ].freeze
    AMBIGUOUS_HELPER_QUERY_STATUSES = %i[unavailable timeout error unknown].freeze
    LOCATION_SERVICES_BLOCKING_STATUSES = %i[location_services_blocked permission_denied].freeze
    HelperQueryResult = Struct.new(
      :payload,
      :location_services_blocked,
      :error_message,
      :status,
      keyword_init: true
    ) do
      def initialize(payload: nil, location_services_blocked: nil, error_message: nil, status: nil)
        result_status = status || default_status(
          location_services_blocked: location_services_blocked,
          error_message:             error_message
        )
        unless HELPER_QUERY_STATUSES.include?(result_status)
          raise ArgumentError, "unknown helper query status: #{result_status.inspect}"
        end

        blocked = location_services_blocked || LOCATION_SERVICES_BLOCKING_STATUSES.include?(result_status)

        super(
          payload:                   payload,
          location_services_blocked: blocked,
          error_message:             error_message,
          status:                    result_status
        )
      end

      def location_services_blocked? = !!location_services_blocked

      def connected? = status == :connected

      def not_connected? = status == :not_connected

      def ambiguous? = AMBIGUOUS_HELPER_QUERY_STATUSES.include?(status)

      def permission_denied? = status == :permission_denied

      def location_services_error?
        return true if location_services_blocked?
        return false if error_message.to_s.empty?

        error_message.downcase.include?('location services')
      end

      private def default_status(location_services_blocked:, error_message:)
        if location_services_blocked
          :location_services_blocked
        elsif error_message
          :error
        else
          :unknown
        end
      end
    end
  end

  # Talks to the compiled macOS helper app used for permission-sensitive
  # read/query operations such as current-network lookups and network scans.
  # Connect/disconnect mutations still run through MacOsSwiftRuntime.
  class MacOsHelperClient
    attr_reader :last_error_message

    # StandardError excludes process-control and VM-level exceptions like Interrupt, SystemExit, and NoMemoryError.
    HELPER_READ_BOUNDARY_ERROR = StandardError

    def initialize(out_stream_proc:, verbose_proc:, macos_version_proc:)
      @out_stream_proc = out_stream_proc
      @verbose_proc = verbose_proc
      @macos_version_proc = macos_version_proc
      @location_warning_emitted = false
      @helper_install_verified = false
      @disabled = false
      @last_error_message = nil
      @last_error_status = nil
    end

    def connected_network_name(timeout_seconds: nil)
      result = execute('current-network', timeout_seconds: timeout_seconds)
      ssid = result.payload.fetch('ssid', nil) if result.payload.is_a?(Hash)
      MacOsHelperBundle::HelperQueryResult.new(
        payload:                   ssid,
        location_services_blocked: result.location_services_blocked,
        error_message:             result.error_message,
        status:                    connected_network_status(result)
      )
    end

    def scan_networks
      result = execute('scan-networks')
      payload = result.payload if result.payload.is_a?(Hash)
      networks = payload&.fetch('networks', []) || []
      MacOsHelperBundle::HelperQueryResult.new(
        payload:                   networks,
        location_services_blocked: result.location_services_blocked,
        error_message:             result.error_message,
        status:                    scan_network_status(result)
      )
    end

    def available?(timeout_seconds: nil)
      helper_availability_status(timeout_seconds: timeout_seconds) == :available
    end

    private def helper_availability_status(timeout_seconds: nil)
      return :unavailable if helper_disabled?

      version = macos_version(timeout_seconds: timeout_seconds)
      return :unknown unless version

      support_status = MacOsHelperBundle.helper_support_status_for_macos_version(version)
      return :available if support_status.supported?

      if support_status.unknown?
        log_verbose("macOS version '#{version}' does not match expected format")
        return :unknown
      end
      :unavailable
    end

    def location_services_blocked?
      return false unless @last_error_status

      MacOsHelperBundle::LOCATION_SERVICES_BLOCKING_STATUSES.include?(@last_error_status)
    end

    private def execute(command, timeout_seconds: nil)
      @last_error_message = nil
      @last_error_status = nil
      deadline = helper_deadline(timeout_seconds)
      timeout_options = -> { helper_timeout_options(deadline) }
      availability_status = helper_availability_status(**timeout_options.())
      unless availability_status == :available
        return MacOsHelperBundle::HelperQueryResult.new(status: availability_status)
      end

      ensure_helper_installed(**timeout_options.())
      return MacOsHelperBundle::HelperQueryResult.new(status: :unavailable) if helper_disabled?
      unless helper_executable_available?
        return MacOsHelperBundle::HelperQueryResult.new(status: :unavailable)
      end

      helper_result = execute_helper_command(command, timeout_seconds: remaining_helper_budget(deadline))
      return MacOsHelperBundle::HelperQueryResult.new(status: :timeout) unless helper_result

      stdout = helper_result[:stdout]
      stderr = helper_result[:stderr]
      status = helper_result[:status]
      payload = parse_json(stdout) unless stdout.to_s.strip.empty?
      payload_status = payload&.fetch('status', nil)
      if helper_error_payload_status?(payload_status)
        log_helper_exit_failure(status, stderr) unless status.success?
        return helper_error_result(payload['error'], helper_status: payload_status)
      end

      unless status.success?
        log_helper_exit_failure(status, stderr)
        return MacOsHelperBundle::HelperQueryResult.new(status: :error)
      end

      return MacOsHelperBundle::HelperQueryResult.new(status: :error) unless payload

      MacOsHelperBundle::HelperQueryResult.new(payload: payload, status: :success)
    rescue Errno::ENOENT => e
      log_verbose("helper executable missing: #{e.message}")
      MacOsHelperBundle::HelperQueryResult.new(status: :unavailable)
    rescue HELPER_READ_BOUNDARY_ERROR => e
      # Helper queries are optional read paths. Keep callers on the fallback
      # path while preserving diagnostics in verbose mode.
      log_verbose("helper command '#{command}' failed: #{e.message}")
      MacOsHelperBundle::HelperQueryResult.new(status: :error)
    end

    private def connected_network_status(result)
      return result.status unless result.status == :success

      payload = result.payload
      return :error unless payload.is_a?(Hash)

      helper_status = payload['status']
      ssid = payload['ssid']
      return :not_connected if helper_status == 'not_connected' && !real_helper_ssid?(ssid)
      return :unknown if helper_status == 'connected' && !real_helper_ssid?(ssid)
      return :unknown unless payload.key?('ssid')
      return :unknown if ssid.nil?
      return :unknown if helper_placeholder_ssid?(ssid)

      :connected
    end

    private def scan_network_status(result)
      return result.status unless result.status == :success

      payload = result.payload
      return :error unless payload.is_a?(Hash)

      payload.key?('networks') ? :success : :unknown
    end

    private def helper_error_payload_status?(status)
      %w[error location_services_blocked permission_denied].include?(status)
    end

    private def helper_error_status(message, helper_status: nil)
      return :location_services_blocked if helper_status == 'location_services_blocked'
      return :permission_denied if helper_status == 'permission_denied'

      normalized_message = message.to_s.downcase
      if normalized_message.include?('location services') &&
          normalized_message.include?('authorization timed out')
        return :timeout
      end

      if normalized_message.include?('location services') &&
          normalized_message.include?('authorization status is unknown')
        return :unknown
      end

      if normalized_message.match?(/location services (?:denied|restricted)/)
        return :location_services_blocked
      end

      :error
    end

    private def helper_error_result(message, helper_status: nil)
      handle_error(message, helper_status: helper_status)
      result_status = helper_error_status(message, helper_status: helper_status)
      MacOsHelperBundle::HelperQueryResult.new(
        error_message: message,
        status:        result_status
      )
    end

    private def log_helper_exit_failure(status, stderr)
      log_verbose("helper exited with status #{status.exitstatus}: #{stderr.strip}")
    end

    private def helper_placeholder_ssid?(ssid)
      value = ssid.to_s.strip
      value.empty? || %w[<hidden> <redacted>].include?(value.downcase)
    end

    private def real_helper_ssid?(ssid)
      !ssid.nil? && !helper_placeholder_ssid?(ssid)
    end

    private def execute_helper_command(command, timeout_seconds: nil)
      WifiWand::MacOsHelperBundle.run_bounded_helper_command(
        helper_executable_path,
        command,
        timeout_seconds: timeout_seconds || WifiWand::MacOsHelperBundle.helper_command_timeout_seconds(command),
        on_timeout:      ->(timed_out_command, timeout_seconds) do
          log_verbose("helper command '#{timed_out_command}' timed out after #{timeout_seconds}s")
        end
      )
    end

    private def helper_executable_available?
      File.executable?(helper_executable_path)
    end

    private def ensure_helper_installed(timeout_seconds: nil)
      return if helper_disabled?
      return if @helper_install_verified

      helper_present = File.executable?(helper_executable_path)
      helper_options = {}
      helper_options[:timeout_seconds] = timeout_seconds if timeout_seconds
      helper_valid = WifiWand::MacOsHelperBundle.helper_installed_and_valid?(**helper_options)
      if helper_valid
        @helper_install_verified = true
        return
      end

      if timeout_seconds
        log_verbose('helper is unavailable during bounded status lookup')
        return
      end

      if helper_present
        log_verbose('existing helper install failed validation; attempting reinstall')
      else
        log_verbose('helper not installed; running installer')
      end

      WifiWand::MacOsHelperBundle.ensure_helper_installed(out_stream: verbose? ? out_stream : nil)
      @helper_install_verified = true
    rescue HELPER_READ_BOUNDARY_ERROR => e
      # Installation is best-effort during normal reads. Disable retries for
      # this process so repeated status checks do not repeatedly mutate files.
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

    private def handle_error(message, helper_status: nil)
      return unless message

      @last_error_message = message
      @last_error_status = helper_error_status(message, helper_status: helper_status)
      if MacOsHelperBundle::LOCATION_SERVICES_BLOCKING_STATUSES.include?(@last_error_status)
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

    private def helper_deadline(timeout_seconds)
      monotonic_now + timeout_seconds if timeout_seconds
    end

    private def remaining_helper_budget(deadline)
      return nil unless deadline

      remaining = deadline - monotonic_now
      remaining.positive? ? remaining : 0
    end

    private def helper_timeout_options(deadline)
      deadline ? { timeout_seconds: remaining_helper_budget(deadline) } : {}
    end

    private def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    private def macos_version(timeout_seconds: nil)
      return unless @macos_version_proc

      if @macos_version_proc.arity.zero?
        @macos_version_proc.call
      else
        @macos_version_proc.call(timeout_in_secs: timeout_seconds)
      end
    end

    private def out_stream = @out_stream_proc&.call

    private def verbose? = !!(@verbose_proc && @verbose_proc.call)
  end
end
