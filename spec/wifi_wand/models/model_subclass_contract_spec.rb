# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe WifiWand::ModelSubclassContract do
  let(:contract) { described_class }

  let(:subclass_with_overrides) do
    Class.new(WifiWand::BaseModel) do
      def self.os_id = :contract_spec

      def bssid = nil

      private def _connected_network_name = nil
    end
  end

  def implements?(subclass, method_name, visibility)
    contract.subclass_implements_required_method?(subclass, method_name, visibility)
  end

  describe '.subclass_implements_required_method?' do
    it 'raises ArgumentError for an unknown visibility requirement' do
      expect { implements?(subclass_with_overrides, :bssid, :protected) }
        .to raise_error(ArgumentError, /Unknown required method visibility: :protected/)
    end

    it 'accepts a public override when public visibility is required' do
      expect(implements?(subclass_with_overrides, :bssid, :public)).to be_truthy
    end

    it 'rejects a private override when public visibility is required' do
      subclass = Class.new(WifiWand::BaseModel) do
        def self.os_id = :contract_spec

        private def bssid = nil
      end

      expect(implements?(subclass, :bssid, :public)).to be_falsey
    end

    it 'accepts a private override when any visibility is allowed' do
      expect(implements?(subclass_with_overrides, :_connected_network_name, :any_visibility)).to be_truthy
    end

    it 'rejects a method that is only inherited from BaseModel' do
      expect(implements?(subclass_with_overrides, :mac_address, :public)).to be_falsey
    end
  end

  describe '.subclass_overrides_method?' do
    it 'is falsey for a method the subclass does not define at all' do
      result = contract.subclass_overrides_method?(subclass_with_overrides, :no_such_method)

      expect(result).to be_falsey
    end
  end

  describe '.verify_required_methods_implemented' do
    it 'names an anonymous subclass and lists every missing method' do
      expect { contract.verify_required_methods_implemented(subclass_with_overrides) }
        .to raise_error(NotImplementedError, /\(anonymous\).*:mac_address/)
    end
  end
end
