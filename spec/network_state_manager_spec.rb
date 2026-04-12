# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'NetworkStateManager' do
  let(:model) { double('model') }
  let(:session) { NetworkStateManager::Session.new(model: model) }

  after do
    NetworkStateManager.clear_session
  end

  describe NetworkStateManager::Session do
    it 'captures and restores state through the provided model' do
      allow(model).to receive(:capture_network_state).and_return({ network_name: 'TestNet' })

      expect(session.capture_state).to eq({ network_name: 'TestNet' })
      expect(model).to receive(:restore_network_state).with({ network_name: 'TestNet' }, fail_silently: false)

      session.restore_state(fail_silently: false)
    end
  end

  describe '.start_session' do
    it 'replaces the implicit session with the provided model' do
      NetworkStateManager.start_session(model: model)

      expect(NetworkStateManager.model).to be(model)
    end
  end
end
