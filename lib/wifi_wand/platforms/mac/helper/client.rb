# frozen_string_literal: true

require 'json'
require_relative '../../../signal_quality'
require_relative '../../../string_predicates'
require_relative '../../../timing'

module WifiWand
  module Platforms
    module Mac
      module Helper
        module Bundle
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
            :signal_quality,
            :status,
            keyword_init: true
          ) do
            def initialize(payload: nil, location_services_blocked: nil, error_message: nil,
              signal_quality: nil, status: nil)
              result_status = status || default_status(
                location_services_blocked: location_services_blocked,
                error_message:             error_message
              )
              unless HELPER_QUERY_STATUSES.include?(result_status)
                raise ArgumentError, "unknown helper query status: #{result_status.inspect}"
              end

              blocked =
                location_services_blocked || LOCATION_SERVICES_BLOCKING_STATUSES.include?(result_status)

              super(
                payload:                   payload,
                location_services_blocked: blocked,
                error_message:             error_message,
                signal_quality:            signal_quality,
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
        # Connect/disconnect mutations still run through SwiftRuntime.
        class Client
          include StringPredicates
          include WifiWand::Timing

          attr_reader :last_error_message

          # StandardError excludes process-control and VM-level exceptions like Interrupt, SystemExit, and NoMemoryError.
          HELPER_READ_BOUNDARY_ERROR = StandardError

          def initialize(out_stream_provider:, verbosity_provider:, macos_version_reader:,
            err_stream_provider: nil, timeout_configuration: Bundle.default_timeout_configuration)
            @out_stream_provider = out_stream_provider
            @err_stream_provider = err_stream_provider
            @verbosity_provider = verbosity_provider
            @macos_version_reader = macos_version_reader
            @timeout_configuration = timeout_configuration
            @location_warning_emitted = false
            @helper_install_verified = false
            @disabled = false
            @last_error_message = nil
            @last_error_status = nil
          end

          def connected_network_name(timeout_seconds: nil)
            result = execute('current-network', timeout_seconds: timeout_seconds)
            ssid = result.payload.fetch('ssid', nil) if result.payload.is_a?(Hash)
            Bundle::HelperQueryResult.new(
              payload:                   ssid,
              location_services_blocked: result.location_services_blocked,
              error_message:             result.error_message,
              signal_quality:            signal_quality_from_payload(result.payload),
              status:                    connected_network_status(result)
            )
          end

          def connected_network_bssid(timeout_seconds: nil)
            result = execute('current-network', timeout_seconds: timeout_seconds)
            bssid = result.payload.fetch('bssid', nil) if result.payload.is_a?(Hash)
            Bundle::HelperQueryResult.new(
              payload:                   bssid,
              location_services_blocked: result.location_services_blocked,
              error_message:             result.error_message,
              status:                    connected_network_bssid_status(result)
            )
          end

          def scan_networks
            result = execute('scan-networks')
            payload = result.payload if result.payload.is_a?(Hash)
            networks = payload&.fetch('networks', []) || []
            Bundle::HelperQueryResult.new(
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

            support_status = Bundle.helper_support_status_for_macos_version(version)
            return :available if support_status.supported?

            if support_status.unknown?
              log_verbose("macOS version '#{version}' does not match expected format")
              return :unknown
            end
            :unavailable
          end

          def location_services_blocked?
            return false unless @last_error_status

            Bundle::LOCATION_SERVICES_BLOCKING_STATUSES.include?(@last_error_status)
          end

          private def execute(command, timeout_seconds: nil)
            @last_error_message = nil
            @last_error_status = nil
            deadline = status_deadline(timeout_seconds)
            timeout_options = -> { helper_timeout_options(deadline) }
            availability_status = helper_availability_status(**timeout_options.())
            unless availability_status == :available
              return Bundle::HelperQueryResult.new(status: availability_status)
            end

            ensure_helper_installed(**timeout_options.())
            return Bundle::HelperQueryResult.new(status: :unavailable) if helper_disabled?
            unless helper_executable_available?
              return Bundle::HelperQueryResult.new(status: :unavailable)
            end

            helper_result = execute_helper_command(command,
              timeout_seconds: status_timeout_for(deadline))
            return Bundle::HelperQueryResult.new(status: :timeout) unless helper_result

            stdout = helper_result[:stdout]
            stderr = helper_result[:stderr]
            status = helper_result[:status]
            payload = parse_json(stdout) unless string_nil_or_blank?(stdout)
            payload_status = payload&.fetch('status', nil)
            if helper_error_payload_status?(payload_status)
              log_helper_exit_failure(status, stderr) unless status.success?
              return helper_error_result(payload['error'],
                helper_status: payload_status,
                payload:       bssid_error_payload(payload))
            end

            unless status.success?
              log_helper_exit_failure(status, stderr)
              return Bundle::HelperQueryResult.new(status: :error)
            end

            return Bundle::HelperQueryResult.new(status: :error) unless payload

            Bundle::HelperQueryResult.new(payload: payload, status: :success)
          rescue Errno::ENOENT => e
            log_verbose("helper executable missing: #{e.message}")
            Bundle::HelperQueryResult.new(status: :unavailable)
          rescue HELPER_READ_BOUNDARY_ERROR => e
            # Helper queries are optional read paths. Keep callers on the fallback
            # path while preserving diagnostics in verbose mode.
            log_verbose("helper command '#{command}' failed: #{e.message}")
            Bundle::HelperQueryResult.new(status: :error)
          end

          private def connected_network_status(result)
            unless result.status == :success
              log_verbose("connected_network_status: upstream status is #{result.status.inspect}")
              return result.status
            end

            payload = result.payload
            unless payload.is_a?(Hash)
              log_verbose('connected_network_status: payload is not a Hash')
              return :error
            end

            helper_status = payload['status']
            ssid = payload['ssid']
            return :not_connected if helper_status == 'not_connected' && !real_helper_ssid?(ssid)

            if helper_status == 'connected' && !real_helper_ssid?(ssid)
              log_verbose(
                "connected_network_status: helper status is 'connected' but SSID is not real: #{ssid.inspect}"
              )
              return :unknown
            end
            unless payload.key?('ssid')
              log_verbose('connected_network_status: payload missing ssid key')
              return :unknown
            end
            if ssid.nil?
              log_verbose('connected_network_status: ssid is nil')
              return :unknown
            end
            if helper_placeholder_ssid?(ssid)
              log_verbose("connected_network_status: ssid is a placeholder: #{ssid.inspect}")
              return :unknown
            end

            :connected
          end

          private def signal_quality_from_payload(payload)
            return nil unless payload.is_a?(Hash)

            rssi = payload['rssi']
            return nil unless rssi.is_a?(Integer)

            SignalQuality.new(value: rssi, unit: :dbm)
          end

          private def connected_network_bssid_status(result)
            return result.status unless result.status == :success || result.payload.is_a?(Hash)

            payload = result.payload
            return :error unless payload.is_a?(Hash)

            helper_status = payload['status']
            bssid = payload['bssid']
            return :not_connected if helper_status == 'not_connected' && string_nil_or_blank?(bssid)
            return :connected unless string_nil_or_blank?(bssid)
            return :unknown if payload.key?('bssid')

            :unknown
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
              log_verbose(
                "helper_error_status: location services authorization status is unknown: #{message.inspect}"
              )
              return :unknown
            end

            if normalized_message.match?(/location services (?:denied|restricted)/)
              return :location_services_blocked
            end

            log_verbose("helper_error_status: unrecognized error message: #{message.inspect}")
            :error
          end

          private def helper_error_result(message, helper_status: nil, payload: nil)
            handle_error(message, helper_status: helper_status)
            result_status = helper_error_status(message, helper_status: helper_status)
            Bundle::HelperQueryResult.new(
              payload:       payload,
              error_message: message,
              status:        result_status
            )
          end

          private def bssid_error_payload(payload)
            payload if payload.is_a?(Hash) && payload.key?('bssid')
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
            Bundle.run_bounded_helper_command(
              helper_executable_path,
              command,
              timeout_seconds:       timeout_seconds || helper_command_timeout_seconds(command),
              on_timeout:            ->(timed_out_command, timeout_seconds) do
                log_verbose("helper command '#{timed_out_command}' timed out after #{timeout_seconds}s")
              end,
              timeout_configuration: @timeout_configuration
            )
          end

          private def helper_command_timeout_seconds(command)
            Bundle.helper_command_timeout_seconds(command, timeout_configuration: @timeout_configuration)
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
            helper_valid = Bundle.helper_installed_and_valid?(
              **helper_options,
              timeout_configuration: @timeout_configuration
            )
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

            Bundle.ensure_helper_installed(
              out_stream:            verbose? ? err_stream : nil,
              timeout_configuration: @timeout_configuration
            )
            @helper_install_verified = true
          rescue HELPER_READ_BOUNDARY_ERROR => e
            # Installation is best-effort during normal reads. Disable retries for
            # this process so repeated status checks do not repeatedly mutate files.
            @helper_install_verified = false
            @disabled = true
            emit_install_failure(e.message, reinstall_required: helper_present)
          end

          private def helper_executable_path = Bundle.installed_executable_path

          private def helper_disabled?
            return true if @disabled

            value = ENV[Bundle::DISABLE_ENV_KEY].to_s.strip.downcase
            %w[1 true yes on].include?(value)
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
            if Bundle::LOCATION_SERVICES_BLOCKING_STATUSES.include?(@last_error_status)
              emit_location_warning
            else
              log_verbose("helper error: #{message}")
            end
          end

          private def emit_location_warning
            return if @location_warning_emitted

            stream = err_stream || $stderr
            if stream
              stream.puts('wifiwand helper: Location Services denied. ' \
                'Run `wifiwand-macos-setup` (or `wifiwand-macos-setup --reinstall`) ' \
                'to grant location access.')
            end
            @location_warning_emitted = true
          end

          private def emit_install_failure(detail, reinstall_required: false)
            stream = err_stream || $stderr
            if stream
              reinstall_hint = if reinstall_required
                ' Run `wifiwand-macos-setup --reinstall` to reinstall it.'
              else
                ''
              end
              stream.puts("wifiwand helper: failed to install helper (#{detail}). " \
                "Helper disabled until the next run.#{reinstall_hint}")
            end
          end

          private def log_verbose(message)
            return unless verbose?

            stream = err_stream || $stderr
            stream.puts("wifiwand helper: #{message}") if stream
          end

          private def helper_timeout_options(deadline)
            deadline ? { timeout_seconds: status_timeout_for(deadline) } : {}
          end

          private def macos_version(timeout_seconds: nil)
            return unless @macos_version_reader

            if @macos_version_reader.arity.zero?
              @macos_version_reader.call
            else
              @macos_version_reader.call(timeout_in_secs: timeout_seconds)
            end
          end

          private def out_stream = @out_stream_provider&.call

          private def err_stream
            @err_stream_provider&.call
          end

          private def verbose? = !!(@verbosity_provider && @verbosity_provider.call)
        end
      end
    end
  end
end
