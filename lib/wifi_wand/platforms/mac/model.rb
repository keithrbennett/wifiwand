# frozen_string_literal: true

require 'shellwords'

require_relative '../../models/base_model'
require_relative '../../errors'
require_relative '../../timing_constants'
require_relative 'helper/swift_runtime'
require_relative 'helper/wifi_transport'
require_relative 'helper/bundle'
require_relative '../../services/status_line_data_builder'
require_relative 'airport_data_provider'
require_relative 'current_network_details'
require_relative 'dns_manager'
require_relative 'interface_detector'
require_relative 'keychain_password_reader'
require_relative 'network_scanner'
require_relative 'network_identity_reader'
require_relative 'status_queries'
require_relative 'system_network_info'


module WifiWand
  module Platforms
    module Mac
      class Model < BaseModel
        SYSTEM_PROFILER_TIMEOUT_SECONDS = AirportDataProvider::SYSTEM_PROFILER_TIMEOUT_SECONDS
        KEYCHAIN_LOOKUP_TIMEOUT_SECONDS = KeychainPasswordReader::DEFAULT_LOOKUP_TIMEOUT_SECONDS
        SUDO_AUTH_CHECK_TIMEOUT_SECONDS = 1
        SUDO_NETWORKSETUP_TIMEOUT_SECONDS = 5
        AIRPORT_COMMAND =
          '/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport'

        # Lazily detected macOS version to avoid OS calls during initialization
        def macos_version(timeout_in_secs: nil)
          @macos_version ||= system_network_info.detect_macos_version(timeout_in_secs: timeout_in_secs)
        end

        def initialize(options = {})
          super
          # Defer macOS version detection until first needed to minimize incidental OS calls
          @macos_version = nil
          @helper_client = nil
          @swift_runtime = nil
          @airport_data_provider = nil
          @dns_manager = nil
          @interface_detector = nil
          @wifi_service_name_source = nil
          @keychain_password_reader = nil
          @network_identity_reader = nil
          @network_scanner = nil
          @current_network_details = nil
          @status_queries = nil
          @system_network_info = nil
        end

        def connection_ready?(network_name)
          with_airport_data_cache_scope { super }
        end

        def wifi_info
          with_airport_data_cache_scope { super }
        end

        def status_line_data(progress_callback: nil)
          with_airport_data_cache_scope do
            StatusLineDataBuilder.call(
              self,
              progress_callback:                          progress_callback,
              runtime_config:                             runtime_config,
              expected_network_errors:                    EXPECTED_NETWORK_ERRORS,
              connectivity_worker_result_timeout_seconds: TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT
            )
          end
        end

        def generate_qr_code(filespec = nil, overwrite: false, delivery_mode: :print, password: nil,
          in_stream: $stdin)
          with_airport_data_cache_scope do
            super(filespec, overwrite: overwrite, delivery_mode: delivery_mode, password: password,
              in_stream: in_stream)
          end
        end

        def self.os_id
          :mac
        end

        # Returns the Wi-Fi service name dynamically (e.g., "Wi-Fi", "AirPort", etc.)
        def wifi_service_name
          return @wifi_service_name if @wifi_service_name && !@wifi_service_name.empty?

          service_name = interface_detector.detected_wifi_service_name(known_interface: @wifi_interface)
          if service_name && !service_name.empty?
            @wifi_service_name_source = :detected
            @wifi_service_name = service_name
          else
            @wifi_service_name_source = :fallback
            @wifi_service_name = 'Wi-Fi'
          end
        end

        # Identifies the (first) wireless network hardware interface in the system, e.g. en0 or en1
        # This may not detect WiFi ports with nonstandard names, such as USB WiFi devices.
        def detect_wifi_interface_using_networksetup(timeout_in_secs: nil)
          result = interface_detector.detect_using_networksetup(
            timeout_in_secs: timeout_in_secs,
            known_interface: @wifi_interface
          )
          update_wifi_detection_state(result)

          result.interface
        end

        # Identifies the (first) wireless network hardware interface in the system, e.g. en0 or en1
        # Prefer the faster networksetup path and fall back to system_profiler if needed.
        # This may not detect WiFi ports with nonstandard names, such as USB WiFi devices.
        def probe_wifi_interface(timeout_in_secs: nil)
          result = interface_detector.probe(
            timeout_in_secs:    timeout_in_secs,
            known_interface:    @wifi_interface,
            known_service_name: @wifi_service_name
          )
          update_wifi_detection_state(result)

          result.interface
        end

        # Returns the network names sorted in descending order of signal strength.
        def _available_network_names
          network_scanner.available_network_names
        end

        def available_network_scan
          raise WifiOffError, 'WiFi is off, cannot scan for available networks.' unless wifi_on?

          _available_network_scan
        end

        def _available_network_scan
          network_scanner.scan
        end

        # Returns data pertaining to "preferred" networks, many/most of which will probably not be available.
        def preferred_networks
          iface = wifi_interface
          lines = run_command(
            ['networksetup', '-listpreferredwirelessnetworks', iface]
          ).stdout.split("\n")
          # Produces something like this, unsorted, and with leading tabs:
          # Preferred networks on en0:
          #         LibraryWiFi
          #         @thePAD/Magma

          lines.delete_at(0)                         # remove title line
          lines.map! { |line| line.gsub("\t", '') }  # remove leading tabs
          lines.sort! { |s1, s2| s1.casecmp(s2) }    # sort alphabetically, case insensitively
          lines
        end

        # Returns whether or not the specified interface is a WiFi interface.
        def is_wifi_interface?(interface)
          interface_detector.is_wifi_interface?(interface)
        end

        def wifi_on?
          system_network_info.wifi_on?
        end

        def associated?
          network_identity_reader.associated?
        end

        def connected?
          network_identity_reader.connected?
        end

        def status_network_identity(timeout_in_secs: nil)
          status_queries.status_network_identity(timeout_in_secs: timeout_in_secs)
        end

        def status_wifi_on?(timeout_in_secs: nil)
          status_queries.status_wifi_on?(timeout_in_secs: timeout_in_secs)
        end

        # Turns WiFi on.
        def wifi_on
          return if wifi_on?

          invalidate_airport_data_cache

          begin
            iface = wifi_interface
            run_command(['networksetup', '-setairportpower', iface, 'on'])
          ensure
            invalidate_airport_data_cache
          end

          wifi_on? ? nil : raise(WifiEnableError)
        end

        # Turns WiFi off.
        def wifi_off
          return unless wifi_on?

          invalidate_airport_data_cache

          begin
            iface = wifi_interface
            run_command(['networksetup', '-setairportpower', iface, 'off'])
          ensure
            invalidate_airport_data_cache
          end

          wifi_on? ? raise(WifiDisableError) : nil
        end

        # Connect mutations flow through the direct Swift-source transport path.
        # That path owns the Swift/CoreWLAN attempt plus fallback to traditional
        # macOS utilities when Swift is unavailable or the connect attempt fails in
        # known ways.
        def _connect(network_name, password = nil)
          invalidate_airport_data_cache
          wifi_transport.connect(network_name, password)
        ensure
          invalidate_airport_data_cache
        end

        # Password lookups on macOS may block on a user-facing keychain approval
        # dialog, so the public lookup API defaults to waiting indefinitely unless
        # a caller explicitly requests a timeout.
        def preferred_network_password(preferred_network_name, timeout_in_secs: nil)
          super
        end

        # @return:
        #   If the network is in the preferred networks list
        #     If a password is associated w/this network, return the password
        #     If not, return nil
        #   else
        #     raise an error
        def _preferred_network_password(preferred_network_name,
          timeout_in_secs: KEYCHAIN_LOOKUP_TIMEOUT_SECONDS)
          keychain_password_reader.password_for(preferred_network_name, timeout_in_secs: timeout_in_secs)
        end

        def _ipv4_addresses
          system_network_info.ipv4_addresses
        end

        def _ipv6_addresses
          system_network_info.ipv6_addresses
        end

        def remove_preferred_network(network_name)
          network_name = network_name.to_s
          iface = wifi_interface
          ensure_sudo_authenticated_for_preferred_network_removal!
          run_command(
            ['sudo', 'networksetup', '-removepreferredwirelessnetwork', iface, network_name],
            raise_on_error:  true,
            timeout_in_secs: SUDO_NETWORKSETUP_TIMEOUT_SECONDS
          )
          [network_name]
        end

        private def ensure_sudo_authenticated_for_preferred_network_removal!
          return if sudo_authentication_cached?

          unless interactive_sudo_authentication_available?
            message = 'Administrator authentication is required to remove a saved WiFi network. ' \
              'Run `sudo -v` in a terminal, then retry.'
            raise SudoAuthenticationError, message
          end

          err_stream.puts 'Administrator authentication is required to remove a saved WiFi network.'
          return if system('sudo', '-v')

          raise SudoAuthenticationError, 'Administrator authentication failed or was cancelled.'
        end

        private def sudo_authentication_cached?
          run_command(
            %w[sudo -n true],
            raise_on_error:  false,
            timeout_in_secs: SUDO_AUTH_CHECK_TIMEOUT_SECONDS
          ).success?
        rescue WifiWand::CommandTimeoutError
          false
        end

        private def interactive_sudo_authentication_available?
          $stdin.respond_to?(:tty?) && $stdin.tty? && $stderr.respond_to?(:tty?) && $stderr.tty?
        end

        # Returns the network currently connected to, or nil if none.

        def connected_network_name
          network_identity_reader.connected_network_name
        end

        def _connected_network_name
          network_identity_reader.connected_network_name_raw
        end

        def network_identity_redacted?
          network_identity_reader.network_identity_redacted?
        end

        def network_identity_redaction_reason
          network_identity_reader.network_identity_redaction_reason
        end

        def helper_client
          @helper_client ||= WifiWand::Platforms::Mac::Helper::Client.new(
            out_stream_proc:    -> { out_stream },
            err_stream_proc:    -> { err_stream },
            verbose_proc:       -> { verbose? },
            macos_version_proc: ->(timeout_in_secs: nil) { macos_version(timeout_in_secs: timeout_in_secs) }
          )
        end

        # Disconnects from the currently connected network. Does not turn off WiFi.
        # Disconnect mutations use the direct Swift-source transport path first,
        # with `ifconfig` fallback when the Swift/CoreWLAN path is unavailable or
        # fails.
        def _disconnect
          invalidate_airport_data_cache
          wifi_transport.disconnect
        ensure
          invalidate_airport_data_cache
        end

        def mac_address
          system_network_info.mac_address
        end

        def bssid
          result = helper_client.connected_network_bssid
          result.payload
        end

        def set_nameservers(nameservers) # rubocop:disable Naming/AccessorMethodName
          dns_manager.set_nameservers(nameservers)
        end

        def open_resource(resource_url) = system_network_info.open_resource(resource_url)

        def nameservers_using_scutil
          dns_manager.nameservers_using_scutil
        end

        def nameservers_using_networksetup
          dns_manager.nameservers_using_networksetup
        end

        def nameservers = nameservers_using_scutil

        # Returns the network interface used for default internet route on macOS
        def default_interface
          system_network_info.default_interface
        end

        def validate_os_preconditions(timeout_in_secs: nil)
          # All core read/status commands are built into macOS. The Swift/CoreWLAN
          # source runtime is mutation-specific and is probed lazily by the
          # connect/disconnect transport.
          :ok
        end

        private def swift_runtime
          @swift_runtime ||= WifiWand::Platforms::Mac::Helper::SwiftRuntime.new(
            command_runner:  ->(*args, **kwargs) { run_command(*args, **kwargs) },
            out_stream_proc: -> { out_stream },
            verbose_proc:    -> { verbose? }
          )
        end

        private def wifi_transport
          @wifi_transport ||= WifiWand::Platforms::Mac::Helper::WifiTransport.new(
            swift_runtime:       swift_runtime,
            command_runner:      ->(*args, **kwargs) { run_command(*args, **kwargs) },
            wifi_interface_proc: -> { wifi_interface },
            out_stream_proc:     -> { out_stream },
            verbose_proc:        -> { verbose? }
          )
        end

        private def airport_data_provider
          @airport_data_provider ||= WifiWand::Platforms::Mac::AirportDataProvider.new(
            owner:          self,
            command_runner: ->(*args, **kwargs) { run_command(*args, **kwargs) }
          )
        end

        private def dns_manager
          @dns_manager ||= WifiWand::Platforms::Mac::DnsManager.new(
            command_runner:    ->(*args, **kwargs) { run_command(*args, **kwargs) },
            service_name_proc: -> { detected_wifi_service_name_for_dns }
          )
        end

        private def interface_detector
          @interface_detector ||= WifiWand::Platforms::Mac::InterfaceDetector.new(
            command_runner: ->(*args, **kwargs) { run_command(*args, **kwargs) }
          )
        end

        private def keychain_password_reader
          @keychain_password_reader ||= WifiWand::Platforms::Mac::KeychainPasswordReader.new(
            command_runner: ->(*args, **kwargs) { run_command(*args, **kwargs) }
          )
        end

        private def network_identity_reader
          @network_identity_reader ||= WifiWand::Platforms::Mac::NetworkIdentityReader.new(
            helper_client_proc:            -> { helper_client },
            command_runner:                ->(*args, **kwargs) { run_command(*args, **kwargs) },
            airport_data_proc:             ->(**kwargs) { airport_data(**kwargs) },
            airport_data_cache_scope_proc: ->(&block) { with_airport_data_cache_scope(&block) },
            wifi_on_proc:                  -> { wifi_on? },
            wifi_interface_proc:           -> { wifi_interface },
            default_interface_proc:        -> { default_interface },
            ipv4_addresses_proc:           -> { _ipv4_addresses },
            airport_command:               AIRPORT_COMMAND
          )
        end

        private def status_queries
          @status_queries ||= WifiWand::Platforms::Mac::StatusQueries.new(
            helper_client_proc:            -> { helper_client },
            command_runner:                ->(*args, **kwargs) { run_command(*args, **kwargs) },
            airport_data_proc:             ->(**kwargs) { airport_data(**kwargs) },
            airport_data_cache_scope_proc: ->(&block) { with_airport_data_cache_scope(&block) },
            cached_wifi_interface_proc:    -> { @wifi_interface },
            cache_wifi_interface_proc:     ->(iface) { @wifi_interface = iface },
            probe_wifi_interface_proc:     ->(**kwargs) { probe_wifi_interface(**kwargs) },
            system_network_info_proc:      -> { system_network_info },
            status_deadline_proc:          ->(timeout_in_secs) { status_deadline(timeout_in_secs) },
            status_timeout_proc:           ->(deadline) { status_timeout_for(deadline) },
            airport_command:               AIRPORT_COMMAND
          )
        end

        private def network_scanner
          @network_scanner ||= WifiWand::Platforms::Mac::NetworkScanner.new(
            helper_client_proc:            -> { helper_client },
            command_runner:                ->(*args, **kwargs) { run_command(*args, **kwargs) },
            airport_data_proc:             -> { airport_data },
            airport_data_cache_scope_proc: ->(&block) { with_airport_data_cache_scope(&block) },
            wifi_interface_proc:           -> { wifi_interface },
            airport_command:               AIRPORT_COMMAND
          )
        end

        private def current_network_details
          @current_network_details ||= WifiWand::Platforms::Mac::CurrentNetworkDetails.new(
            airport_data_proc:             -> { airport_data },
            airport_data_cache_scope_proc: ->(&block) { with_airport_data_cache_scope(&block) },
            connected_network_name_proc:   -> { _connected_network_name },
            wifi_interface_proc:           -> { wifi_interface },
            security_normalizer_proc:      ->(security_text) { canonical_security_type_from(security_text) }
          )
        end

        private def system_network_info
          @system_network_info ||= WifiWand::Platforms::Mac::SystemNetworkInfo.new(
            command_runner:      ->(*args, **kwargs) { run_command(*args, **kwargs) },
            wifi_interface_proc: -> { wifi_interface },
            out_stream_proc:     -> { out_stream },
            verbose_proc:        -> { verbose? }
          )
        end

        private def detected_wifi_service_name_for_dns
          if @wifi_service_name && !@wifi_service_name.empty? && @wifi_service_name_source != :fallback
            return @wifi_service_name
          end

          service_name = interface_detector.detected_wifi_service_name(known_interface: @wifi_interface)
          if service_name && !service_name.empty?
            @wifi_service_name = service_name
            @wifi_service_name_source = :detected
          end
          service_name
        end

        private def update_wifi_detection_state(result)
          @wifi_interface = result.interface if result.interface && !result.interface.empty?
          if result.service_name && !result.service_name.empty?
            @wifi_service_name = result.service_name
            @wifi_service_name_source = :detected
          end
        end

        private def with_airport_data_cache_scope(&)
          airport_data_provider.with_cache_scope(&)
        end

        private def airport_data(timeout_in_secs: nil)
          airport_data_provider.data(timeout_in_secs: timeout_in_secs)
        end

        private def invalidate_airport_data_cache
          airport_data_provider.invalidate_cache
        end

        # Gets the security type of the currently connected network.
        # @return [String, nil] The security type: "WPA", "WPA2", "WPA3", "WEP",
        #   "NONE" for open networks, or nil if not connected/not found
        public def connection_security_type
          current_network_details.connection_security_type
        end

        # Checks if the currently connected network is a hidden network.
        # A hidden network does not broadcast its SSID.
        # @return [Boolean] true if connected to a hidden network, false otherwise
        public def network_hidden?
          current_network_details.network_hidden?
        end
      end
    end
  end
end
