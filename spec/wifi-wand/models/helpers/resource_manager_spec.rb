require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi-wand/models/helpers/resource_manager'

describe WifiWand::Helpers::ResourceManager do
  let(:resource_manager) { described_class.new }
  
  describe '#open_resources' do
    it 'lazily loads resources from YAML file' do
      resources = resource_manager.open_resources
      expect(resources).to be_a(WifiWand::Helpers::ResourceManager::OpenResources)
      expect(resources).not_to be_empty
      
      # Verify it contains expected resource codes
      codes = resources.map(&:code)
      expect(codes).to include('ipw', 'spe', 'cap', 'ipl', 'libre', 'this')
    end
    
    it 'memoizes the resources on subsequent calls' do
      first_call = resource_manager.open_resources
      second_call = resource_manager.open_resources
      expect(first_call).to be(second_call) # same object identity
    end
  end
  
  describe '#available_resources_help' do
    it 'returns formatted help text' do
      help = resource_manager.available_resources_help
      expect(help).to include("Please specify a resource to open:")
      expect(help).to include("'ipw' (What is My IP)")
      expect(help).to include("'spe' (Speed Test)")
    end
  end
  
  describe '#invalid_codes_error' do
    it 'formats error message for single invalid code' do
      error = resource_manager.invalid_codes_error(['invalid'])
      expect(error).to include("Invalid resource code: 'invalid'")
      expect(error).to include("Valid codes are:")
      expect(error).to include("'ipw' (What is My IP)")
    end
    
    it 'formats error message for multiple invalid codes' do
      error = resource_manager.invalid_codes_error(['invalid1', 'invalid2'])
      expect(error).to include("Invalid resource codes: 'invalid1', 'invalid2'")
      expect(error).to include("Valid codes are:")
    end
  end
  
  describe '#open_resources_by_codes' do
    let(:mock_model) { double('model') }
    
    before do
      allow(mock_model).to receive(:open_resource)
    end
    
    context 'with empty codes' do
      it 'returns empty arrays' do
        result = resource_manager.open_resources_by_codes(mock_model)
        expect(result[:opened_resources]).to be_empty
        expect(result[:invalid_codes]).to be_empty
      end
    end
    
    context 'with nil model' do
      it 'raises ArgumentError' do
        expect { resource_manager.open_resources_by_codes(nil, 'ipw') }.to raise_error(ArgumentError, 'Model cannot be nil')
      end
    end
    
    context 'with valid codes' do
      it 'opens resources and returns opened resources' do
        result = resource_manager.open_resources_by_codes(mock_model, 'ipw', 'cap')
        
        expect(mock_model).to have_received(:open_resource).twice
        expect(result[:opened_resources].size).to eq(2)
        expect(result[:opened_resources].map(&:code)).to eq(['ipw', 'cap'])
        expect(result[:invalid_codes]).to be_empty
      end
    end
    
    context 'with invalid codes' do
      it 'returns invalid codes without opening anything' do
        result = resource_manager.open_resources_by_codes(mock_model, 'invalid1', 'invalid2')
        
        expect(mock_model).not_to have_received(:open_resource)
        expect(result[:opened_resources]).to be_empty
        expect(result[:invalid_codes]).to eq(['invalid1', 'invalid2'])
      end
    end
    
    context 'with mixed valid and invalid codes' do
      it 'opens valid resources and reports invalid ones' do
        result = resource_manager.open_resources_by_codes(mock_model, 'ipw', 'invalid', 'cap')
        
        expect(mock_model).to have_received(:open_resource).twice
        expect(result[:opened_resources].size).to eq(2)
        expect(result[:opened_resources].map(&:code)).to eq(['ipw', 'cap'])
        expect(result[:invalid_codes]).to eq(['invalid'])
      end
    end
    
    
    it 'converts codes to strings' do
      result = resource_manager.open_resources_by_codes(mock_model, :ipw, 123)
      
      expect(result[:invalid_codes]).to eq(['123']) # 123 converted to '123' and not found
      expect(result[:opened_resources].size).to eq(1) # :ipw converted to 'ipw' and found
    end
  end
end

describe WifiWand::Helpers::ResourceManager::OpenResource do
  describe '#help_string' do
    it 'formats help string correctly' do
      resource = described_class.new('ipw', 'https://www.whatismyip.com', 'What is My IP')
      expect(resource.help_string).to eq("'ipw' (What is My IP)")
    end
  end
end

describe WifiWand::Helpers::ResourceManager::OpenResources do
  let(:resources) do
    described_class.new([
      WifiWand::Helpers::ResourceManager::OpenResource.new('ipw', 'https://www.whatismyip.com', 'What is My IP'),
      WifiWand::Helpers::ResourceManager::OpenResource.new('spe', 'http://speedtest.net/', 'Speed Test')
    ])
  end
  
  describe '#find_by_code' do
    it 'finds resource by code' do
      resource = resources.find_by_code('ipw')
      expect(resource).not_to be_nil
      expect(resource.code).to eq('ipw')
      expect(resource.url).to eq('https://www.whatismyip.com')
    end
    
    it 'returns nil for non-existent code' do
      resource = resources.find_by_code('nonexistent')
      expect(resource).to be_nil
    end
  end
  
  describe '#help_string' do
    it 'formats help string for all resources' do
      help = resources.help_string
      expect(help).to eq("'ipw' (What is My IP), 'spe' (Speed Test)")
    end
  end
end

describe 'ResourceManager error handling and edge cases' do
  let(:resource_manager) { WifiWand::Helpers::ResourceManager.new }
  
  describe '#load_resources' do
    it 'raises error when YAML file is missing' do
      allow(resource_manager).to receive(:resource_file_path).and_return('/nonexistent/path/open_resources.yml')
      
      expect { resource_manager.open_resources }.to raise_error(Errno::ENOENT, /Resource file not found/)
    end
    
    it 'raises error when YAML file has invalid structure' do
      invalid_yaml_path = '/tmp/invalid_resources.yml'
      File.write(invalid_yaml_path, "invalid: yaml: structure:")
      
      allow(resource_manager).to receive(:resource_file_path).and_return(invalid_yaml_path)
      
      expect { resource_manager.open_resources }.to raise_error(ArgumentError, /Invalid YAML/)
      
      File.delete(invalid_yaml_path) if File.exist?(invalid_yaml_path)
    end
    
    it 'raises error when YAML file is missing resources key' do
      invalid_yaml_path = '/tmp/missing_resources_key.yml'
      File.write(invalid_yaml_path, "other_key: value")
      
      allow(resource_manager).to receive(:resource_file_path).and_return(invalid_yaml_path)
      
      expect { resource_manager.open_resources }.to raise_error(ArgumentError, /must contain a 'resources' key/)
      
      File.delete(invalid_yaml_path) if File.exist?(invalid_yaml_path)
    end
  end
  
  describe 'resource validation' do
    it 'handles resources with missing fields gracefully' do
      incomplete_yaml_path = '/tmp/incomplete_resources.yml'
      File.write(incomplete_yaml_path, <<~YAML)
        resources:
          - code: "test"
            # missing url and desc
      YAML
      
      allow(resource_manager).to receive(:resource_file_path).and_return(incomplete_yaml_path)
      
      expect { resource_manager.open_resources }.not_to raise_error
      resource = resource_manager.open_resources.first
      expect(resource.code).to eq('test')
      expect(resource.url).to be_nil
      expect(resource.description).to be_nil
      
      File.delete(incomplete_yaml_path) if File.exist?(incomplete_yaml_path)
    end
  end
end