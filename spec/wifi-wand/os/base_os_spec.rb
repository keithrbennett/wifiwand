# frozen_string_literal: true

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

  describe 'error messages' do
    it 'provides meaningful NonSubclassInstantiationError message' do
      begin
        BaseOs.new(:test, 'test')
      rescue WifiWand::BaseOs::NonSubclassInstantiationError => e
        expect(e.to_s).to include('can only be instantiated by subclasses')
      end
    end

    it 'raises MethodNotImplementedError for abstract methods' do
      test_subclass = Class.new(BaseOs) do
        def initialize(id, display_name)
          super(id, display_name)
        end
      end
      
      instance = test_subclass.new(:test_id, 'Test Display Name')
      
      expect { instance.current_os_is_this_os? }.to raise_error(WifiWand::BaseOs::MethodNotImplementedError)
      expect { instance.create_model({}) }.to raise_error(WifiWand::BaseOs::MethodNotImplementedError)
    end
  end
end

end