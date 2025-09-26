# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/connection_manager'

describe WifiWand::ConnectionManager do
  let(:mock_model) { double('model') }
  subject { described_class.new(mock_model, verbose: false) }
  
  before do
    # Mock common model methods
    allow(mock_model).to receive(:connected_network_name).and_return(nil)
    allow(mock_model).to receive(:preferred_networks).and_return([])
    allow(mock_model).to receive(:wifi_on)
    allow(mock_model).to receive(:_connect)
    allow(mock_model).to receive(:till)
  end

  describe '#initialize' do
    it 'stores model and verbose settings' do
      manager = described_class.new(mock_model, verbose: true)
      expect(manager.model).to eq(mock_model)
      expect(manager.verbose_mode).to be true
    end
    
    it 'defaults verbose to false' do
      manager = described_class.new(mock_model)
      expect(manager.verbose_mode).to be false
    end
  end

  describe '#connect' do
    context 'with invalid network name' do
      it 'raises InvalidNetworkNameError for nil network name' do
        expect { subject.connect(nil) }.to raise_error(WifiWand::InvalidNetworkNameError)
      end
      
      it 'raises InvalidNetworkNameError for empty network name' do
        expect { subject.connect('') }.to raise_error(WifiWand::InvalidNetworkNameError)
      end
    end
    
    context 'when already connected to target network' do
      before do
        allow(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
      end
      
      it 'returns early without attempting connection' do
        expect(mock_model).not_to receive(:wifi_on)
        expect(mock_model).not_to receive(:_connect)
        
        subject.connect('TestNetwork')
      end
    end
    
    context 'with successful connection' do
      before do
        allow(mock_model).to receive(:connected_network_name).and_return(nil, 'TestNetwork')
      end
      
      it 'turns on wifi and connects to network' do
        expect(mock_model).to receive(:wifi_on).ordered
        expect(mock_model).to receive(:_connect).with('TestNetwork', nil).ordered
        
        subject.connect('TestNetwork')
      end
      
      it 'accepts symbol network names' do
        expect(mock_model).to receive(:_connect).with('TestNetwork', nil)
        
        subject.connect(:TestNetwork)
      end
      
      it 'handles provided password' do
        expect(mock_model).to receive(:_connect).with('TestNetwork', 'password123')
        
        subject.connect('TestNetwork', 'password123')
      end
    end
    
    context 'with saved passwords' do
      before do
        allow(mock_model).to receive(:preferred_networks).and_return(['SavedNetwork'])
        allow(mock_model).to receive(:preferred_network_password).with('SavedNetwork').and_return('saved_password')
        allow(mock_model).to receive(:connected_network_name).and_return(nil, 'SavedNetwork')
      end
      
      it 'uses saved password when no password provided and network is preferred' do
        expect(mock_model).to receive(:_connect).with('SavedNetwork', 'saved_password')
        
        subject.connect('SavedNetwork')
        expect(subject.last_connection_used_saved_password?).to be true
      end
      
      it 'does not use saved password when password is provided' do
        expect(mock_model).to receive(:_connect).with('SavedNetwork', 'manual_password')
        
        subject.connect('SavedNetwork', 'manual_password')
        expect(subject.last_connection_used_saved_password?).to be false
      end
      
      it 'handles keychain access errors gracefully', :os_mac do
        allow(mock_model).to receive(:preferred_network_password).and_raise(StandardError, 'Keychain access denied')
        expect(mock_model).to receive(:_connect).with('SavedNetwork', nil)
        
        subject.connect('SavedNetwork')
        expect(subject.last_connection_used_saved_password?).to be false
      end
    end
    
    context 'when connection verification fails' do
      before do
        allow(mock_model).to receive(:connected_network_name).and_return(nil, 'WrongNetwork')
      end
      
      it 'raises NetworkConnectionError when connected to wrong network' do
        expect { subject.connect('TestNetwork') }.to raise_error(WifiWand::NetworkConnectionError) do |error|
          expect(error.message).to include('TestNetwork')
          expect(error.message).to include('WrongNetwork')
        end
      end
      
      it 'raises NetworkConnectionError when no connection established' do
        allow(mock_model).to receive(:connected_network_name).and_return(nil, nil)
        
        expect { subject.connect('TestNetwork') }.to raise_error(WifiWand::NetworkConnectionError) do |error|
          expect(error.message).to include('unable to connect to any network')
        end
      end
    end
  end
  
  describe '#last_connection_used_saved_password?' do
    it 'returns false initially' do
      expect(subject.last_connection_used_saved_password?).to be false
    end
    
    it 'tracks saved password usage correctly' do
      allow(mock_model).to receive(:preferred_networks).and_return(['SavedNetwork'])
      allow(mock_model).to receive(:preferred_network_password).and_return('saved_password')
      allow(mock_model).to receive(:connected_network_name).and_return(nil, 'SavedNetwork')
      
      subject.connect('SavedNetwork')
      expect(subject.last_connection_used_saved_password?).to be true
    end
    
    it 'resets flag on each connection attempt' do
      # First connection uses saved password
      allow(mock_model).to receive(:preferred_networks).and_return(['SavedNetwork'])
      allow(mock_model).to receive(:preferred_network_password).and_return('saved_password')
      allow(mock_model).to receive(:connected_network_name).and_return(nil, 'SavedNetwork')
      
      subject.connect('SavedNetwork')
      expect(subject.last_connection_used_saved_password?).to be true
      
      # Second connection with manual password should reset flag
      allow(mock_model).to receive(:connected_network_name).and_return(nil, 'SavedNetwork')
      subject.connect('SavedNetwork', 'manual_password')
      expect(subject.last_connection_used_saved_password?).to be false
    end
  end

  describe 'resolve_password edge cases' do
    it 'treats preferred networks as empty when preferred_networks raises' do
      allow(mock_model).to receive(:preferred_networks).and_raise(StandardError, 'boom')
      password, used_saved = subject.send(:resolve_password, 'AnyNet', nil)
      expect(password).to be_nil
      expect(used_saved).to be false
    end
  end
  
  describe 'integration with real model', :disruptive do
    subject { create_test_model }

    it 'can be accessed through model' do
      expect(subject.connection_manager).to be_a(described_class)
    end

    it 'connects properly through BaseModel delegation' do
      # Mock the connection to avoid real network calls
      allow(subject).to receive(:wifi_on?)
      allow(subject).to receive(:connected_network_name).and_return(nil, 'TestNetwork')
      allow(subject).to receive(:preferred_networks).and_return([])
      allow(subject).to receive(:wifi_on)
      allow(subject).to receive(:_connect)
      
      expect { subject.connect('TestNetwork') }.not_to raise_error
    end
  end
end
