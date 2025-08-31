require_relative '../spec_helper'
require_relative '../../lib/wifi-wand/models/ubuntu_model'
require_relative '../../lib/wifi-wand/models/mac_os_model'

module WifiWand
  describe 'Error Classes' do

    # Mock OS calls to prevent real system interaction during non-disruptive tests
    before(:each) do
      # Mock detect_wifi_interface for both OS types
      allow_any_instance_of(WifiWand::UbuntuModel).to receive(:detect_wifi_interface).and_return('wlp0s20f3')
      allow_any_instance_of(WifiWand::MacOsModel).to receive(:detect_wifi_interface).and_return('en0') if defined?(WifiWand::MacOsModel)
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
        { klass: NetworkNotFoundError,          args: ['MyNet'],                      message: "Network 'MyNet' not found. No networks are currently available" },
        { klass: NetworkNotFoundError,          args: ['MyNet', ['Net1', 'Net2']],    message: "Network 'MyNet' not found. Available networks: Net1, Net2" },
        { klass: NetworkConnectionError,        args: ['MyNet'],                      message: "Failed to connect to network 'MyNet'" },
        { klass: NetworkConnectionError,        args: ['MyNet', 'bad password'],      message: "Failed to connect to network 'MyNet': bad password" },
        { klass: WifiInterfaceError,            args: ['en1'],                        message: "WiFi interface 'en1' not found. Ensure WiFi hardware is present and drivers are installed" },
        { klass: WifiInterfaceError,            args: [],                             message: "No WiFi interface found. Ensure WiFi hardware is present and drivers are installed" },
        { klass: WifiEnableError,               args: [],                             message: "WiFi could not be enabled. Check hardware and permissions" },
        { klass: WifiDisableError,              args: [],                             message: "WiFi could not be disabled. Check permissions" },
        { klass: WaitTimeoutError,              args: ['connecting', 10],             message: "Timed out after 10 seconds waiting for connecting" },
        { klass: InvalidIPAddressError,         args: ['999.999.999.999'],            message: "Invalid IP address(es): 999.999.999.999" },
        { klass: InvalidIPAddressError,         args: [['1.2.3.4.5', 'abc']],         message: "Invalid IP address(es): 1.2.3.4.5, abc" },
        { klass: InvalidNetworkNameError,       args: ['MyNet'],                      message: "Invalid network name: 'MyNet'. Network name cannot be empty" },
        { klass: InvalidInterfaceError,         args: ['eth0'],                       message: "'eth0' is not a valid WiFi interface" },
        { klass: UnsupportedSystemError,        args: [],                             message: "Unsupported system" },
        { klass: UnsupportedSystemError,        args: ['macOS 12.0', 'macOS 11.0'],   message: "Unsupported system. Requires macOS 12.0 or later, found macOS 11.0" },
        { klass: CommandNotFoundError,          args: ['iw'],                         message: "Missing required system command(s): iw" },
        { klass: CommandNotFoundError,          args: [['iw', 'nmcli']],              message: "Missing required system command(s): iw, nmcli" },
        { klass: KeychainAccessDeniedError,     args: ['MyNet'],                      message: "Keychain access denied for network 'MyNet'. Please grant access when prompted" },
        { klass: KeychainAccessCancelledError,  args: ['MyNet'],                      message: "Keychain access cancelled for network 'MyNet'" },
        { klass: KeychainNonInteractiveError,   args: ['MyNet'],                      message: "Cannot access keychain for network 'MyNet' in non-interactive environment" },
        { klass: MultipleOSMatchError,          args: [['macOS', 'Ubuntu']],          message: "Multiple OS matches found: macOS, Ubuntu. This should not happen" },
        { klass: NoSupportedOSError,            args: [],                             message: "No supported operating system detected. WifiWand supports macOS and Ubuntu Linux" },
        { klass: PreferredNetworkNotFoundError, args: ['MyNet'],                      message: "Network 'MyNet' not in preferred networks list" },
        { klass: ConfigurationError,            args: ['A config is wrong'],          message: 'A config is wrong' },
        { klass: BadCommandError,               args: ['This is a bad command'],      message: 'This is a bad command' },
      ]

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

    # Integration tests - verify methods actually raise expected errors
    describe 'Method integration tests' do
      let(:model) { create_test_model }

      error_raising_test_cases = [
        { method: :connect, args: [''], error: InvalidNetworkNameError },
        { method: :connect, args: [nil], error: InvalidNetworkNameError },
        {
          method: :connect, args: ['TestNetwork'], error: NetworkConnectionError,
          before: -> {
            allow(model).to receive(:wifi_on).and_return(true)
            allow(model).to receive(:_connect).with('TestNetwork', nil).and_return(true)
            allow(model).to receive(:connected_network_name).and_return('DifferentNetwork')
          }
        },
        {
          method: :preferred_network_password, args: ['NonExistentNetwork'], error: PreferredNetworkNotFoundError,
          before: -> { allow(model).to receive(:preferred_networks).and_return([]) }
        },
        {
          method: :wifi_on, args: [], error: WifiEnableError,
          before: -> {
            allow(model).to receive(:run_os_command).and_return(true)
            allow(model).to receive(:wifi_on?).and_return(false)
            allow(model).to receive(:till).and_raise(WifiWand::WaitTimeoutError.new(:on, 5))
          }
        },
        {
          method: :wifi_off, args: [], error: WifiDisableError,
          before: -> {
            allow(model).to receive(:run_os_command).and_return(true)
            allow(model).to receive(:wifi_on?).and_return(true)
            allow(model).to receive(:till).and_raise(WifiWand::WaitTimeoutError.new(:off, 5))
          }
        },
        {
          method: :validate_os_preconditions, args: [], error: CommandNotFoundError, os_tag: :os_ubuntu,
          before: -> {
            allow(model).to receive(:command_available_using_which?).with("iw").and_return(false)
            allow(model).to receive(:command_available_using_which?).with("nmcli").and_return(false)
          }
        },
      ]

      error_raising_test_cases.each do |test_case|
        it "raises #{test_case[:error]} when calling #{test_case[:method]} with #{test_case[:args]}", test_case[:os_tag] || {} do
          # Run the before block in the context of the test
          instance_exec(&test_case[:before]) if test_case[:before]

          # Special case for methods that are not public
          if model.private_methods.include?(test_case[:method])
            expect { model.send(test_case[:method], *test_case[:args]) }.to raise_error(test_case[:error])
          else
            expect { model.public_send(test_case[:method], *test_case[:args]) }.to raise_error(test_case[:error])
          end
        end
      end

      # These tests are harder to make table-driven due to their complexity
      describe 'Complex initialization errors' do
        it 'raises WifiInterfaceError when no wifi interface detected during initialization' do
          current_model_class = create_test_model.class
          allow_any_instance_of(current_model_class).to receive(:detect_wifi_interface).and_return(nil)
          expect { create_test_model }.to raise_error(WifiInterfaceError)
        end

        it 'raises InvalidInterfaceError when specified interface is invalid during initialization' do
          current_model_class = create_test_model.class
          allow_any_instance_of(current_model_class).to receive(:is_wifi_interface?).with('invalid_interface').and_return(false)
          expect { create_test_model(wifi_interface: 'invalid_interface') }.to raise_error(InvalidInterfaceError)
        end
      end

      describe 'macOS specific errors', :os_mac do
        let(:mac_model) { create_mac_os_test_model }

        keychain_error_test_cases = [
          { error: KeychainAccessDeniedError, exit_code: 45, message: 'access denied' },
          { error: KeychainAccessCancelledError, exit_code: 128, message: 'user cancelled' },
          { error: KeychainNonInteractiveError, exit_code: 51, message: 'non-interactive' },
        ]

        keychain_error_test_cases.each do |test_case|
          it "raises #{test_case[:error]} for exit code #{test_case[:exit_code]}" do
            allow(mac_model).to receive(:run_os_command).with(/security find-generic-password/).and_raise(
              WifiWand::CommandExecutor::OsCommandError.new(test_case[:exit_code], "security", test_case[:message])
            )
            expect { mac_model.send(:_preferred_network_password, 'TestNetwork') }.to raise_error(test_case[:error])
          end
        end
      end
    end
  end
end
