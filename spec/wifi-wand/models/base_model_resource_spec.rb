require_relative '../../spec_helper'

describe 'BaseModel Resource Management' do
  let(:mock_resource_manager) { double('resource_manager') }
  let(:model_class) do
    Class.new(WifiWand::BaseModel) do
      def self.os_id
        :test
      end
      
      # Mock required methods
      def open_resource(url); end
      def open_application(app_name); end
      
      # Stub other required methods to prevent NotImplementedError
      %i[
        default_interface detect_wifi_interface is_wifi_interface?
        mac_address nameservers os_level_preferred_network_password
        preferred_networks remove_preferred_network set_nameservers
        validate_os_preconditions wifi_off wifi_on wifi_on?
        _available_network_names _connected_network_name _connect
        _disconnect _ip_address
      ].each do |method_name|
        define_method(method_name) { nil }
      end
    end
  end
  
  let(:model) { model_class.new(OpenStruct.new(verbose: false)) }
  
  describe 'resource manager delegation' do
    before do
      allow(WifiWand::Helpers::ResourceManager).to receive(:new).and_return(mock_resource_manager)
    end
    
    it 'delegates #available_resources_help to resource manager' do
      expect(mock_resource_manager).to receive(:available_resources_help).and_return('help text')
      
      result = model.available_resources_help
      expect(result).to eq('help text')
    end
    
    it 'delegates #open_resources_by_codes to resource manager' do
      expect(mock_resource_manager).to receive(:open_resources_by_codes)
        .with(model, 'code1', 'code2')
        .and_return({ opened_resources: [], invalid_codes: [] })
      
      model.open_resources_by_codes('code1', 'code2')
    end
    
    it 'memoizes resource manager instance' do
      expect(WifiWand::Helpers::ResourceManager).to receive(:new).once.and_return(mock_resource_manager)
      
      model.resource_manager
      model.resource_manager # second call should use memoized instance
    end
  end
end