require_relative '../../lib/wifi-wand/errors'

module WifiWand
  describe 'Error Classes' do
    
    # Mock OS calls to prevent real system interaction during non-disruptive tests
    before(:each) do
      # Mock detect_wifi_interface for both OS types
      allow_any_instance_of(WifiWand::UbuntuModel).to receive(:detect_wifi_interface).and_return('wlp0s20f3')
      allow_any_instance_of(WifiWand::MacOsModel).to receive(:detect_wifi_interface).and_return('en0') if defined?(WifiWand::MacOsModel)
    end
    
    # Test inheritance
    describe 'Error inheritance' do
      it 'all errors inherit from base Error class' do
        error_classes = [
          CommandNotFoundError,
          InvalidInterfaceError,
          InvalidIPAddressError,
          InvalidNetworkNameError,
          KeychainAccessCancelledError,
          KeychainAccessDeniedError,
          KeychainNonInteractiveError,
          MultipleOSMatchError,
          NetworkConnectionError,
          NetworkNotFoundError,
          NoSupportedOSError,
          PreferredNetworkNotFoundError,
          UnsupportedSystemError,
          WifiDisableError,
          WifiEnableError,
          WifiInterfaceError
        ]
        
        error_classes.each do |error_class|
          expect(error_class.superclass).to eq(Error)
        end
      end
    end
    
    # Integration tests - verify methods actually raise expected errors
    describe 'Method integration tests' do
      
      describe 'InvalidNetworkNameError from connect method' do
        let(:model) { create_test_model }
        
        it 'raises InvalidNetworkNameError for empty network name' do
          expect { model.connect('') }.to raise_error(InvalidNetworkNameError)
        end
        
        it 'raises InvalidNetworkNameError for nil network name' do
          expect { model.connect(nil) }.to raise_error(InvalidNetworkNameError)
        end
      end
      
      # Note: InvalidInterfaceError and WifiInterfaceError are harder to test reliably
      # in integration tests due to complex system state requirements. They are
      # tested in the actual usage scenarios in the existing ubuntu_model_spec.rb
      
      describe 'NetworkConnectionError from connect method' do
        let(:model) { create_test_model }
        
        it 'raises NetworkConnectionError when connection verification fails' do
          # Mock the methods to simulate connection failure
          allow(model).to receive(:wifi_on).and_return(true)
          allow(model).to receive(:_connect).with('TestNetwork', nil).and_return(true)
          allow(model).to receive(:connected_network_name).and_return('DifferentNetwork')
          
          expect { model.connect('TestNetwork') }.to raise_error(NetworkConnectionError)
        end
      end
      
      describe 'PreferredNetworkNotFoundError from preferred_network_password' do
        let(:model) { create_test_model }
        
        it 'raises PreferredNetworkNotFoundError when network not in preferred list' do
          # Mock preferred_networks to return empty list
          allow(model).to receive(:preferred_networks).and_return([])
          
          expect { model.preferred_network_password('NonExistentNetwork') }.to raise_error(PreferredNetworkNotFoundError)
        end
      end
      
      describe 'WifiEnableError from wifi_on method' do
        let(:model) { create_test_model }
        
        it 'raises WifiEnableError when wifi fails to turn on' do
          # Mock wifi_on? to return false after wifi_on command
          allow(model).to receive(:run_os_command).and_return(true)
          allow(model).to receive(:wifi_on?).and_return(false)
          
          expect { model.wifi_on }.to raise_error(WifiEnableError)
        end
      end
      
      describe 'WifiDisableError from wifi_off method' do
        let(:model) { create_test_model }
        
        it 'raises WifiDisableError when wifi fails to turn off' do
          # Mock wifi_on? to return true after wifi_off command  
          allow(model).to receive(:run_os_command).and_return(true)
          allow(model).to receive(:wifi_on?).and_return(true)
          
          expect { model.wifi_off }.to raise_error(WifiDisableError)
        end
      end
      
      describe 'WifiInterfaceError from detect_wifi_interface' do
        it 'raises WifiInterfaceError when no wifi interface detected', :os_macos do
          model = create_mac_os_test_model
          # Mock networksetup output to simulate no wifi interface
          allow(model).to receive(:run_os_command).with("networksetup -listallhardwareports").and_return("No wifi interface found")
          
          expect { model.send(:detect_wifi_interface) }.to raise_error(WifiInterfaceError)
        end
        
        it 'raises WifiInterfaceError when no wifi interface detected during initialization' do
          # Mock detect_wifi_interface to return nil during model creation
          # Use the actual current OS model class
          current_model_class = create_test_model.class
          allow_any_instance_of(current_model_class).to receive(:detect_wifi_interface).and_return(nil)
          
          expect { create_test_model }.to raise_error(WifiInterfaceError)
        end
      end
      
      describe 'InvalidInterfaceError from BaseModel' do
        it 'raises InvalidInterfaceError when specified interface is invalid during initialization' do
          # Mock is_wifi_interface? to return false during model creation
          current_model_class = create_test_model.class  
          allow_any_instance_of(current_model_class).to receive(:is_wifi_interface?).with('invalid_interface').and_return(false)
          
          expect { create_test_model(wifi_interface: 'invalid_interface') }.to raise_error(InvalidInterfaceError)
        end
      end
      
      describe 'CommandNotFoundError from Ubuntu model initialization' do  
        it 'raises CommandNotFoundError when command availability check fails', :os_ubuntu do
          model = create_test_model
          
          # Mock command_available_using_which? to return false for required commands
          allow(model).to receive(:command_available_using_which?).with("iw").and_return(false) 
          allow(model).to receive(:command_available_using_which?).with("nmcli").and_return(false)
          
          expect { model.send(:validate_os_preconditions) }.to raise_error(CommandNotFoundError)
        end
      end
      
      describe 'Keychain errors from macOS model', :os_macos do
        let(:model) { create_mac_os_test_model }
        
        it 'raises KeychainAccessDeniedError when keychain access denied' do
          # Mock security command to return access denied exit code (45)
          allow(model).to receive(:run_os_command).with(/security find-generic-password/).and_raise(
            WifiWand::CommandExecutor::OsCommandError.new(45, "security", "access denied")
          )
          
          expect { model.os_level_preferred_network_password('TestNetwork') }.to raise_error(KeychainAccessDeniedError)
        end
        
        it 'raises KeychainAccessCancelledError when user cancels keychain access' do
          # Mock security command to return user cancelled exit code (128)
          allow(model).to receive(:run_os_command).with(/security find-generic-password/).and_raise(
            WifiWand::CommandExecutor::OsCommandError.new(128, "security", "user cancelled")
          )
          
          expect { model.os_level_preferred_network_password('TestNetwork') }.to raise_error(KeychainAccessCancelledError)
        end
        
        it 'raises KeychainNonInteractiveError in non-interactive environment' do
          # Mock security command to return non-interactive exit code (51)  
          allow(model).to receive(:run_os_command).with(/security find-generic-password/).and_raise(
            WifiWand::CommandExecutor::OsCommandError.new(51, "security", "non-interactive")
          )
          
          expect { model.os_level_preferred_network_password('TestNetwork') }.to raise_error(KeychainNonInteractiveError)
        end
      end
    end
  end
end