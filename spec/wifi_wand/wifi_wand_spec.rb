# frozen_string_literal: true

RSpec.describe WifiWand do
  describe 'top-level require' do
    it 'loads WifiWand::Error for library consumers' do
      expect(defined?(WifiWand::Error)).to eq('constant')
    end
  end

  describe '.create_model' do
    it 'delegates to Platforms::Selector.create_model_for_current_os with Hash options' do
      hash_options = { verbose: false, wifi_interface: 'wlan0' }
      expect(WifiWand::Platforms::Selector)
        .to receive(:create_model_for_current_os).with(hash_options)
        .and_return(:mock_hash_model)

      expect(described_class.create_model(hash_options)).to eq(:mock_hash_model)
    end

    it 'delegates to Platforms::Selector.create_model_for_current_os with default options' do
      expect(WifiWand::Platforms::Selector)
        .to receive(:create_model_for_current_os)
        .and_return(:default_mock_model)

      expect(described_class.create_model).to eq(:default_mock_model)
    end

    it 'delegates to Platforms::Selector.create_model_for_current_os with an Options struct' do
      options = WifiWand::BaseModel::Options.new(verbose: false, wifi_interface: 'wlan0')
      expect(WifiWand::Platforms::Selector)
        .to receive(:create_model_for_current_os).with(options)
        .and_return(:mock_options_model)

      expect(described_class.create_model(options)).to eq(:mock_options_model)
    end

    it 'does not validate options itself, deferring to the model layer' do
      invalid_options = Object.new
      expect(WifiWand::Platforms::Selector)
        .to receive(:create_model_for_current_os).with(invalid_options)
        .and_return(:mock_model)

      expect { described_class.create_model(invalid_options) }.not_to raise_error
    end
  end
end
