# frozen_string_literal: true

require 'socket'
require 'timeout'

require_relative '../errors'
require_relative '../runtime_config'
require_relative '../string_predicates'

module WifiWand
  class DisconnectManager
    include StringPredicates

    EXPECTED_NETWORK_ERRORS = [
      SocketError,
      IOError,
      Errno::ECONNREFUSED,
      Errno::ETIMEDOUT,
      Errno::EHOSTUNREACH,
      Errno::ENETUNREACH,
      Timeout::Error,
    ].freeze

    NETWORK_OPERATION_COMMAND_ERRORS = [
      WifiWand::CommandExecutor::OsCommandError,
      WifiWand::CommandTimeoutError,
      WifiWand::CommandNotFoundError,
      WifiWand::CommandSpawnError,
    ].freeze

    attr_reader :model
    private attr_reader :runtime_config

    def initialize(model, runtime_config: nil)
      @model = model
      @runtime_config = runtime_config || RuntimeConfig.new
    end

    def disconnect
      original_network_name = nil
      return nil unless model.wifi_on?

      # Capture the SSID before asking the OS to disconnect so timeout handling
      # can still report which network we expected to leave.
      association_state = disconnect_association_state
      original_network_name = association_state.fetch(:network_name)
      return nil unless association_state.fetch(:associated)

      model._disconnect
      # A disconnect only counts as success once the interface actually reports
      # no active association, mirroring the postcondition checks used elsewhere.
      wait_until_disassociated!(timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT)
      # On some systems the SSID can disappear briefly during state churn before
      # the radio re-associates. Require a short stable disassociation window so
      # a transient nil SSID does not count as a successful disconnect.
      unless disassociated_stable?
        raise(WifiWand::WaitTimeoutError.new(
          action:  :disassociated,
          timeout: disconnect_stability_window_in_secs
        ))
      end

      nil
    rescue *NETWORK_OPERATION_COMMAND_ERRORS => e
      raise(disconnect_command_failure(original_network_name, e))
    rescue WifiWand::WaitTimeoutError
      # Re-check the SSID after a timeout so callers get the best available
      # diagnostic when the disconnect command ran but the radio stayed associated.
      current_network_name = begin
        model.connected_network_name
      rescue WifiWand::Error
        nil
      end
      lingering_network_name = current_network_name || original_network_name
      reason = lingering_network_name ? "still associated with '#{lingering_network_name}'" :
        'interface remained associated'
      raise(NetworkDisconnectionError.new(network_name: lingering_network_name, reason: reason))
    end

    # Returns true when the model considers the requested network fully usable.
    # Subclasses may override this to require stronger OS-specific readiness.
    def disconnect_stability_window_in_secs
      WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL * 2
    end

    def disassociated_stable?
      deadline = monotonic_now + disconnect_stability_window_in_secs

      loop do
        return false if disconnect_association_state.fetch(:associated)
        return true if monotonic_now >= deadline

        sleep(WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL)
      end
    end

    private

    def disconnect_association_state
      network_name = model.connected_network_name
      unless string_nil_or_empty?(network_name)
        return { associated: true, network_name: network_name }
      end

      # If the SSID is unavailable but the platform can still report an active
      # connection, try the disconnect instead of treating the operation as a
      # no-op. Unlike associated?, connected? does not intentionally collapse
      # command failures into false for this mutating preflight.
      {
        associated:   disconnect_associated?,
        network_name: nil,
      }
    rescue *NETWORK_OPERATION_COMMAND_ERRORS
      raise
    rescue WifiWand::MacOsRedactionError
      {
        associated:   disconnect_associated?,
        network_name: nil,
      }
    rescue WifiWand::Error
      # If the SSID cannot be read for a non-command reason, the safest
      # mutating behavior is to attempt the disconnect and let the
      # command/postcondition path determine the outcome.
      {
        associated:   true,
        network_name: nil,
      }
    end

    def disconnect_associated?
      model.disconnect_associated?
    end

    def wait_until_disassociated!(timeout_in_secs:)
      deadline = monotonic_now + timeout_in_secs

      loop do
        return nil unless disconnect_association_state.fetch(:associated)

        remaining_time = deadline - monotonic_now
        raise(WaitTimeoutError.new(action: :disassociated, timeout: timeout_in_secs)) if remaining_time <= 0

        sleep([WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL, remaining_time].min)
      end
    end

    def disconnect_command_failure(network_name, error)
      NetworkDisconnectionError.new(network_name: network_name, reason: command_error_detail(error))
    end

    def command_error_detail(error)
      detail = error.display_message if error.respond_to?(:display_message)
      detail = error.message if string_nil_or_empty?(detail)
      detail.to_s
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
