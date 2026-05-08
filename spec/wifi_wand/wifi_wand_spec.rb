# frozen_string_literal: true

RSpec.describe WifiWand do
  describe 'top-level require' do
    it 'loads WifiWand::Error for library consumers' do
      expect(defined?(WifiWand::Error)).to eq('constant')
    end
  end

  describe '.create_model' do
    it 'delegates to OperatingSystems.create_model_for_current_os with Hash options' do
      hash_options = { verbose: false, wifi_interface: 'wlan0' }
      expect(WifiWand::OperatingSystems)
        .to receive(:create_model_for_current_os).with(hash_options)
        .and_return(:mock_hash_model)

      expect(described_class.create_model(hash_options)).to eq(:mock_hash_model)
    end

    it 'delegates to OperatingSystems.create_model_for_current_os with default options' do
      expect(WifiWand::OperatingSystems)
        .to receive(:create_model_for_current_os)
        .and_return(:default_mock_model)

      expect(described_class.create_model).to eq(:default_mock_model)
    end

    it 'rejects non-Hash options' do
      expect do
        described_class.create_model(Object.new)
      end.to raise_error(ArgumentError, /options must be a Hash/)
    end
  end
end
