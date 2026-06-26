# frozen_string_literal: true

require 'socket'
require 'stringio'
require_relative 'env_boolean'
require_relative 'network_state_manager'
require_relative '../../lib/wifi_wand/command_line_options'
require_relative '../../lib/wifi_wand/platforms/selector'
require_relative '../../lib/wifi_wand/platforms/ubuntu/model'
require_relative '../../lib/wifi_wand/platforms/mac/model'

module TestHelpers
  BASE_MODEL_REQUIRED_METHOD_DEFINITIONS = {
    bssid:                       -> {},
    connected?:                  -> { false },
    connection_security_type:    -> {},
    default_interface:           -> {},
    is_wifi_interface?:          ->(_interface_name) { true },
    mac_address:                 -> {},
    nameservers:                 -> { [] },
    network_hidden?:             -> { false },
    open_resource:               ->(*) {},
    preferred_networks:          -> { [] },
    remove_preferred_network:    ->(*) {},
    set_nameservers:             ->(*) {},
    signal_quality:              nil,
    validate_os_preconditions:   -> {},
    wifi_off:                    -> {},
    wifi_on:                     -> {},
    wifi_on?:                    -> { true },
    _available_network_names:    -> { [] },
    _connected_network_name:     -> {},
    _connect:                    ->(*) {},
    _disconnect:                 -> {},
    _ipv4_addresses:             -> { [] },
    _ipv6_addresses:             -> { [] },
    _preferred_network_password: ->(*) {},
  }.freeze

  def restore_network_state = NetworkStateManager.restore_state

  def network_state = NetworkStateManager.network_state

  def os_command_error(exitstatus:, command:, text: nil)
    WifiWand::CommandExecutor::OsCommandError.new(exitstatus: exitstatus, command: command, text: text)
  end

  def network_connection_error(network_name:, reason: nil)
    WifiWand::NetworkConnectionError.new(network_name: network_name, reason: reason)
  end

  def wait_timeout_error(action:, timeout:)
    WifiWand::WaitTimeoutError.new(action: action, timeout: timeout)
  end

  def define_base_model_required_methods(klass, except: [], probe_wifi_interface: 'wlan0')
    skipped_methods = Array(except)
    method_definitions = BASE_MODEL_REQUIRED_METHOD_DEFINITIONS.merge(
      probe_wifi_interface: proc { probe_wifi_interface }
    )

    klass.class_eval do
      method_definitions.each do |method_name, implementation|
        next if skipped_methods.include?(method_name)

        if implementation.respond_to?(:call)
          define_method(method_name, &implementation)
        else
          define_method(method_name) { implementation }
        end
      end
    end

    klass
  end

  def expect_process_dead(pid)
    expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
  end

  def kill_and_reap_process(pid)
    return unless pid

    Process.kill('KILL', pid)
  rescue Errno::ESRCH
    nil
  ensure
    begin
      Process.wait(pid, Process::WNOHANG) if pid
    rescue Errno::ECHILD
      nil
    end
  end

  # Helper method to create models with verbose configuration
  # Handles missing system commands gracefully for CI environments
  def create_test_model(options = {})
    merged_options = merge_verbose_options(options)
    current_os = WifiWand::Platforms::Selector.current_os
    raise WifiWand::NoSupportedOSError unless current_os

    case current_os.id
    when :ubuntu
      model = WifiWand::Platforms::Ubuntu::Model.new(merged_options)
      # Mock command availability to prevent missing utility errors in CI
      # Mock WiFi interface detection to prevent hardware detection failures in CI
      # This can be overridden by individual tests that need to test interface detection failures
      allow(model.command_executor).to receive(:command_available?).and_return(true)
      allow(model).to receive(:probe_wifi_interface).and_return('wlp0s20f3')
      model.init
      model
    when :mac
      # Mac models don't have the same command validation issues, but need interface detection stubbing
      # Stub interface detection methods to prevent real network calls during model creation
      allow_any_instance_of(WifiWand::Platforms::Mac::Model)
        .to receive(:probe_wifi_interface).and_return('en0')
      interface_detector = instance_double(
        WifiWand::Platforms::Mac::InterfaceDetector,
        is_wifi_interface?: true,
        wifi_service_name:  'Wi-Fi'
      )
      allow_any_instance_of(WifiWand::Platforms::Mac::Model).to receive(:interface_detector)
        .and_return(interface_detector)
      unless uses_real_env?
        empty_result = WifiWand::Platforms::Mac::Helper::Bundle::HelperQueryResult.new
        helper_client = instance_double(
          WifiWand::Platforms::Mac::Helper::Client,
          connected_network_name: empty_result,
          scan_networks:          empty_result
        )
        allow(WifiWand::Platforms::Mac::Helper::Client).to receive(:new).and_return(helper_client)
      end
      WifiWand::Platforms::Mac::Model.create_model(merged_options)
    else
      raise WifiWand::NoSupportedOSError
    end
  end

  # Helper method to create specific OS models with verbose configuration
  def create_ubuntu_test_model(options = {}) = WifiWand::Platforms::Ubuntu::Model.new(merge_verbose_options(options))

  def create_mac_os_test_model(options = {}) = WifiWand::Platforms::Mac::Model.new(merge_verbose_options(options))

  def running_jruby?
    RUBY_PLATFORM == 'java'
  end

  # Returns a timeout value appropriate for tests that start a real external
  # process. JRuby (via the JVM) has substantially slower startup and warm-up
  # time than CRuby, so a larger timeout is used there.
  def external_process_timeout
    running_jruby? ? 10 : 5
  end

  def wait_for(timeout: 5, interval: 0.1, description: 'condition')
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    loop do
      return if yield # The block returns true, so we exit successfully

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time > timeout
        raise "Timeout after #{timeout}s waiting for #{description}"
      end

      sleep(interval)
    end
  end

  def uses_real_env?
    current_example = RSpec.current_example
    example_metadata = current_example&.metadata || {}
    example_real_env = example_metadata[:real_env] ||
      example_metadata[:real_env_read_only] ||
      example_metadata[:real_env_read_write]
    group_real_env = all_example_groups.any? do |group|
      metadata = group.metadata
      metadata[:real_env] || metadata[:real_env_read_only] || metadata[:real_env_read_write]
    end
    example_real_env || group_real_env
  end

  private def all_example_groups
    [self.class] + self.class.parent_groups
  end

  private def merge_verbose_options(options = {})
    # Check for verbose mode from environment variable (as default)
    verbose = EnvBoolean.enabled?(ENV, 'WIFIWAND_VERBOSE', default: false)

    # Merge environment default with provided options (options override env)
    { verbose: verbose }.merge(options)
  end

  # Suppress stdout/stderr within the given block
  private def silence_output
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield $stdout, $stderr
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end

  # Color assertion constants for testing TTY-aware output
  ANSI_COLOR_REGEX = /\e\[\d+m/
  GREEN_TEXT_REGEX = /\e\[32m.*\e\[0m/
  RED_TEXT_REGEX = /\e\[31m.*\e\[0m/
  YELLOW_TEXT_REGEX = /\e\[33m.*\e\[0m/
  CYAN_TEXT_REGEX = /\e\[36m.*\e\[0m/

  def strip_ansi(text) = text.to_s.gsub(/\e\[[\d;]*m/, '')

  # Factory method for creating standard CLI mock model with common methods
  private def create_standard_mock_model(overrides = {})
    defaults = {
      verbose?:                             false,
      wifi_on?:                             true,
      wifi_off:                             nil,
      wifi_on:                              nil,
      available_network_names:              %w[TestNet1 TestNet2],
      wifi_info:                            { 'status' => 'connected' },
      bssid:                                '00:11:22:33:44:55',
      internet_connectivity_state:          :reachable,
      connected_network_name:               'TestNetwork',
      disconnect:                           nil,
      connect:                              nil,
      cycle_network:                        nil,
      nameservers:                          ['8.8.8.8', '1.1.1.1'],
      set_nameservers:                      nil,
      preferred_networks:                   %w[Network1 Network2],
      preferred_network_password:           'password123',
      public_ip_address:                    '203.0.113.10',
      public_ip_country:                    'TH',
      public_ip_info:                       { 'address' => '203.0.113.10', 'country' => 'TH' },
      random_mac_address:                   '02:00:00:00:00:01',
      remove_preferred_networks:            ['RemovedNet'],
      till:                                 nil,
      last_connection_used_saved_password?: false,
      available_resources_help:             'Available resources help text',
      open_resources_by_codes:              { opened_resources: [], invalid_codes: [] },
      resource_manager:                     double('resource_manager', invalid_codes_error: 'Invalid codes'),
      generate_qr_code:                     'TestNetwork-qr-code.png',
      render_qr_code:                       "[QR-ANSI]\n",
      print_qr_code:                        nil,
    }
    double('model', defaults.merge(overrides))
  end

  # Factory method for creating mock OS with a model
  private def create_mock_os_with_model(model = nil)
    model ||= create_standard_mock_model
    double('os', create_model: model)
  end

  # Factory method for creating CLI options
  private def create_cli_options(overrides = {})
    defaults = {
      verbose:          false,
      wifi_interface:   nil,
      interactive_mode: false,
      post_processor:   nil,
    }
    WifiWand::CommandLineOptions.new(**defaults, **overrides)
  end

  # Helper for mocking Socket.tcp failures
  private def mock_socket_connection_failure
    allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED)
  end

  # Helper for mocking Socket.tcp success
  private def mock_socket_connection_success
    allow(Socket).to receive(:tcp).and_yield
  end

  # Helper for mocking IPSocket.getaddress failures
  private def mock_dns_resolution_failure
    allow(IPSocket).to receive(:getaddress).and_raise(SocketError)
  end

  # Helper for mocking IPSocket.getaddress success
  private def mock_dns_resolution_success(address = '1.2.3.4')
    allow(IPSocket).to receive(:getaddress).and_return(address)
  end

  # Helper for stubbing short connectivity timeouts for fast tests
  private def stub_short_connectivity_timeouts
    stub_const('WifiWand::TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT', 0.05)
    stub_const('WifiWand::TimingConstants::TCP_CONNECTION_TIMEOUT', 0.01)
    stub_const('WifiWand::TimingConstants::DNS_RESOLUTION_TIMEOUT', 0.01)
    stub_const('WifiWand::TimingConstants::HTTP_CONNECTIVITY_TIMEOUT', 0.01)
  end

  # Starts a minimal one-shot HTTP server on an OS-assigned local port.
  # Accepts a single connection, reads the HTTP request headers, and writes a
  # response with the given status code and body before closing.  Yields the
  # chosen port number so the caller can build a URL pointing at it.
  # Network access stays fully within the loopback interface, so tests that use
  # this helper remain hermetic.
  private def with_local_http_server(response_code:, response_body: '')
    server_thread = nil
    server = TCPServer.new('127.0.0.1', 0)
    port   = server.addr[1]

    server_thread = Thread.new do
      client = server.accept
      loop { break if client.gets.strip.empty? }
      client.write(local_http_response(response_code, response_body))
      client.close
    rescue
      nil
    ensure
      begin
        server.close
      rescue
        nil
      end
    end

    yield port
  ensure
    begin
      server.close
    rescue
      nil
    end
    server_thread&.join(2)
  end

  private def local_http_response(response_code, response_body)
    reason = response_code == 302 ? 'Found' : 'OK'
    headers = [
      "HTTP/1.1 #{response_code} #{reason}",
      "Content-Length: #{response_body.bytesize}",
      'Connection: close',
    ]
    headers << 'Location: http://captive.portal/login' if response_code == 302
    "#{headers.join("\r\n")}\r\n\r\n#{response_body}"
  end
end
