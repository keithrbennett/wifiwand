# frozen_string_literal: true

require 'ostruct'

RSpec.describe WifiWand do
  describe '.create_model' do
    it 'delegates to OperatingSystems.create_model_for_current_os with provided options' do
      options = OpenStruct.new(verbose: true, wifi_interface: 'en0')
      expect(WifiWand::OperatingSystems)
        .to receive(:create_model_for_current_os)
        .with(options)
        .and_return(:mock_model)

      expect(WifiWand.create_model(options)).to eq(:mock_model)
    end

    it 'delegates to OperatingSystems.create_model_for_current_os with default options' do
      expect(WifiWand::OperatingSystems)
        .to receive(:create_model_for_current_os) do |opts|
          expect(opts).to be_a(OpenStruct)
          :default_mock_model
        end

      expect(WifiWand.create_model).to eq(:default_mock_model)
    end
  end
end

