require_relative '../../../lib/wifi-wand/os/base_os'

module WifiWand

describe BaseOs do

  describe 'private constructor' do
    it 'prevents direct instantiation via new' do
      expect { BaseOs.new(:test_id, 'Test Display Name') }.to raise_error(WifiWand::BaseOs::NonSubclassInstantiationError)
    end
  end

  describe 'inheritance behavior' do
    it 'allows subclass instantiation' do
      # Create a test subclass to verify inheritance works
      test_subclass = Class.new(BaseOs) do
        def initialize(id, display_name)
          super(id, display_name)
        end
      end
      
      expect { test_subclass.new(:test_id, 'Test Display Name') }.not_to raise_error
    end
  end
end

end