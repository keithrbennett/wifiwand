# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/wifi-wand/models/ubuntu_model'
require_relative '../../lib/wifi-wand/models/mac_os_model'

module WifiWand
  describe 'Error Classes' do
    # Mock OS calls to prevent real system interaction during ordinary tests
    before do
      # Mock interface discovery for both OS types
      allow_any_instance_of(WifiWand::UbuntuModel).to receive(:probe_wifi_interface).and_return('wlp0s20f3')
      if defined?(WifiWand::MacOsModel)
        allow_any_instance_of(WifiWand::MacOsModel).to receive(:probe_wifi_interface).and_return('en0')
      end

      # Mock NetworkConnectivityTester to prevent real network calls
      allow_any_instance_of(WifiWand::NetworkConnectivityTester).to receive(:internet_connectivity_state)
        .and_return(:reachable)
      allow_any_instance_of(WifiWand::NetworkConnectivityTester).to receive(:tcp_connectivity?)
        .and_return(true)
      allow_any_instance_of(WifiWand::NetworkConnectivityTester).to receive(:dns_working?).and_return(true)
    end

    # Test inheritance - ensures all error classes inherit from base Error class
    describe 'Error inheritance' do
      it 'all error classes defined in WifiWand module inherit from the base Error class' do
        # Use Ruby reflection to find all constants that are classes ending in 'Error'
        all_error_classes = WifiWand.constants
          .map { |const_name| WifiWand.const_get(const_name) }
          .select { |const| const.is_a?(Class) && const.name.end_with?('Error') }

        # Exclude base class and any future exceptions
        excluded_classes = [WifiWand::Error]
        error_classes = all_error_classes - excluded_classes

        # Ensure we're testing a significant number of error classes
        expect(error_classes.size).to be > 15

        error_classes.each do |error_class|
          expect(error_class).to be < Error
          expect(error_class).to be < WifiWand::Error,
            "#{error_class.name} should inherit from WifiWand::Error"
        end
      end
    end

    # Unit tests for each error class to verify message formatting
    describe 'Unit tests for each error class' do
      error_test_cases = [
        [NetworkNotFoundError,          ['MyNet'],
          "Network 'MyNet' not found. No networks are currently available"],
        [NetworkNotFoundError,          ['MyNet', %w[Net1 Net2]],
          "Network 'MyNet' not found. Available networks: Net1, Net2"],
        [NetworkConnectionError,        ['MyNet'],
          "Failed to connect to network 'MyNet'"],
        [NetworkConnectionError,        ['MyNet', 'bad password'],
          "Failed to connect to network 'MyNet': bad password"],
        [WifiInterfaceError,            ['en1'],
          "WiFi interface 'en1' not found. Ensure WiFi hardware is present and drivers are installed"],
        [WifiInterfaceError,            [],
          'No WiFi interface found. Ensure WiFi hardware is present and drivers are installed'],
        [WifiEnableError,               [],
          'WiFi could not be enabled. Check hardware and permissions'],
        [WifiDisableError,              [],
          'WiFi could not be disabled. Check permissions'],
        [WaitTimeoutError,              ['connecting', 10],
          'Timed out after 10 seconds waiting for connecting'],
        [InvalidIPAddressError,         ['999.999.999.999'],
          'Invalid IP address(es): 999.999.999.999'],
        [InvalidIPAddressError,         [['1.2.3.4.5', 'abc']],
          'Invalid IP address(es): 1.2.3.4.5, abc'],
        [InvalidNetworkNameError,       ['MyNet'],
          "Invalid network name: 'MyNet'. Network name cannot be empty"],
        [InvalidNetworkPasswordError,   ['secret', 'Password cannot exceed 63 characters'],
          'Invalid network password: Password cannot exceed 63 characters'],
        [InvalidInterfaceError,         ['eth0'],
          "'eth0' is not a valid WiFi interface"],
        [CommandNotFoundError,          ['iw'],
          'Missing required system command(s): iw'],
        [CommandNotFoundError,          [%w[iw nmcli]],
          'Missing required system command(s): iw, nmcli'],
        [KeychainAccessDeniedError,     ['MyNet'],
          "Keychain access denied for network 'MyNet'. Please grant access when prompted"],
        [KeychainAccessCancelledError,  ['MyNet'],
          "Keychain access cancelled for network 'MyNet'"],
        [KeychainNonInteractiveError,   ['MyNet'],
          "Cannot access keychain for network 'MyNet' in non-interactive environment"],
        [MultipleOSMatchError,          [%w[macOS Ubuntu]],
          'Multiple OS matches found: macOS, Ubuntu. This should not happen'],
        [NoSupportedOSError,            [],
          'No supported operating system detected. WifiWand supports macOS and Ubuntu Linux'],
        [PreferredNetworkNotFoundError, ['MyNet'],
          "Network 'MyNet' not in preferred networks list"],
        [ConfigurationError,            ['A config is wrong'],
          'A config is wrong'],
        [KeychainError,                 ['custom keychain error'],
          'custom keychain error'],
        [BadCommandError,               ['This is a bad command'],
          'This is a bad command'],
      ].map { |klass, args, message| { klass:, args:, message: } }
      error_test_cases.each do |test_case|
        it "formats the message correctly for #{test_case[:klass]} with args #{test_case[:args]}" do
          err = test_case[:klass].new(*test_case[:args])
          expect(err.message).to eq(test_case[:message])
        end
      end

      it 'BaseOs errors provide meaningful messages' do
        non_subclass_error = BaseOs::NonSubclassInstantiationError.new
        expect(non_subclass_error.to_s).to include('can only be instantiated by subclasses')

        method_not_impl_error = BaseOs::MethodNotImplementedError.new
        expect(method_not_impl_error.to_s).to include('must be implemented in, and called on, a subclass')
      end
    end

    # Additional unit tests for error classes with branching behavior
    describe PublicIPLookupError do
      it 'formats message when HTTP status is provided' do
        err = described_class.new('503', 'Service Unavailable')
        expect(err.message).to include('HTTP error fetching public IP info: 503 Service Unavailable')
        expect(err.status_code).to eq('503')
        expect(err.status_message).to eq('Service Unavailable')
      end

      it 'uses a generic message when no status is provided' do
        err = described_class.new
        expect(err.message).to eq('Public IP lookup failed')
      end
    end

    # Integration tests - verify methods actually raise expected errors
    describe 'Method integration tests' do
      let(:model) { create_test_model }

      error_raising_test_cases = [
        { method: :connect, args: [''], error: InvalidNetworkNameError },
        { method: :connect, args: [nil], error: InvalidNetworkNameError },
        {
          method: :connect, args: ['TestNetwork'], error: NetworkConnectionError,
          before: -> {
            allow(model).to receive(:_connect).with('TestNetwork', nil).and_return(true)
            allow(model).to receive_messages(wifi_on: true, connected_network_name: 'DifferentNetwork')
            # Mock the connection manager to prevent real connection attempts
            allow(model.connection_manager).to receive(:perform_connection)
            allow(model.connection_manager).to receive(:verify_connection)
              .and_raise(WifiWand::NetworkConnectionError.new(
                'TestNetwork', "connected to 'DifferentNetwork' instead"))
          }
        },
        {
          method: :preferred_network_password, args: ['__WIFIWAND_TEST_NON_EXISTENT_NETWORK__'],
          error: PreferredNetworkNotFoundError,
          before: -> {
            # Ensure membership check fails regardless of underlying OS/network state
            allow(model).to receive(:has_preferred_network?).and_return(false)
            allow_any_instance_of(model.class).to receive(:has_preferred_network?).and_return(false)

            # Ensure our test exercises the real wrapper method, not a global stub
            # Only un-stub on macOS where the global stub is applied
            if defined?($compatible_os_tag) && $compatible_os_tag == :os_mac
              allow_any_instance_of(WifiWand::MacOsModel)
                .to receive(:preferred_network_password)
                .and_call_original
            end
          }
        },
        {
          method: :wifi_on, args: [], error: WifiEnableError,
          before: -> {
            allow(model).to receive_messages(run_os_command: command_result(stdout: ''), wifi_on?: false)
            allow(model).to receive(:till).and_raise(WifiWand::WaitTimeoutError.new(:wifi_on, 5))
          }
        },
        {
          method: :wifi_off, args: [], error: WifiDisableError,
          before: -> {
            allow(model).to receive_messages(run_os_command: command_result(stdout: ''), wifi_on?: true)
            allow(model).to receive(:till).and_raise(WifiWand::WaitTimeoutError.new(:wifi_off, 5))
          }
        },
      ]

      error_raising_test_cases.each do |test_case|
        t = test_case
        it "raises #{t[:error]} when calling #{t[:method]} with #{t[:args]}", t[:os_tag] || {} do
          # Run the before block in the context of the test
          instance_exec(&t[:before]) if t[:before]

          # Special case for methods that are not public
          if model.private_methods.include?(t[:method])
            expect { model.send(t[:method], *t[:args]) }.to raise_error(t[:error])
          else
            expect { model.public_send(t[:method], *t[:args]) }.to raise_error(t[:error])
          end
        end
      end

      it 'raises CommandNotFoundError from UbuntuModel#validate_os_preconditions ' \
        'when required commands are missing' do
        ubuntu_model = create_ubuntu_test_model
        allow(ubuntu_model).to receive(:command_available?).with('iw').and_return(false)
        allow(ubuntu_model).to receive(:command_available?).with('nmcli').and_return(false)
        expect { ubuntu_model.validate_os_preconditions }.to raise_error(CommandNotFoundError)
      end

      # These tests are harder to make table-driven due to their complexity
      describe 'Complex initialization errors' do
        it 'raises WifiInterfaceError when no wifi interface detected during initialization' do
          current_os = WifiWand::OperatingSystems.current_os
          merged_options = merge_verbose_options({})

          case current_os.id
          when :ubuntu
            model = WifiWand::UbuntuModel.new(merged_options)
            allow(model).to receive_messages(command_available?: true, probe_wifi_interface: nil)
            expect { model.init }.to raise_error(WifiInterfaceError)
          when :mac
            model = WifiWand::MacOsModel.new(merged_options)
            allow(model).to receive(:probe_wifi_interface).and_return(nil)
            expect { model.init }.to raise_error(WifiInterfaceError)
          else
            skip 'Test not applicable for current OS'
          end
        end

        it 'raises InvalidInterfaceError when specified interface is invalid during initialization' do
          current_model_class = create_test_model.class
          allow_any_instance_of(current_model_class).to receive(:is_wifi_interface?)
            .with('invalid_interface').and_return(false)
          expect { create_test_model(wifi_interface: 'invalid_interface') }
            .to raise_error(InvalidInterfaceError)
        end
      end

      describe 'macOS specific errors' do
        let(:mac_model) { create_mac_os_test_model }

        # These tests ensure the application gracefully handles specific failures from the external
        # `security` command-line tool when accessing the macOS Keychain. By mapping distinct exit codes to
        # user-friendly errors, we make the application more robust and provide clearer feedback to the user.
        keychain_error_test_cases = [
          { error: KeychainAccessDeniedError, exit_code: 45, message: 'access denied' },
          { error: KeychainAccessCancelledError, exit_code: 128, message: 'user cancelled' },
          { error: KeychainNonInteractiveError, exit_code: 51, message: 'non-interactive' },
        ]

        keychain_error_test_cases.each do |test_case|
          it "raises #{test_case[:error]} for exit code #{test_case[:exit_code]}" do
            # This mock intercepts calls to `run_os_command` to simulate `security` command failures.
            allow(mac_model).to receive(:run_os_command) do |*args|
              command = args.first

              # For any command other than `security`, return a default success-like string to prevent
              # unrelated test failures. This is an early return, making the mock's intent clearer.
              unless command.is_a?(Array) && command.first == 'security'
                next 'Wi-Fi Power (en0): On'
              end

              # When the `security` command is called, simulate its failure by raising an
              # OsCommandError with the specific exit code for the current test case.
              raise WifiWand::CommandExecutor::OsCommandError.new(
                test_case[:exit_code], 'security', test_case[:message])
            end
            expect { mac_model.send(:_preferred_network_password, 'TestNetwork') }
              .to raise_error(test_case[:error])
          end
        end
      end
    end
  end
end
