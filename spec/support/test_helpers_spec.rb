# frozen_string_literal: true

require 'spec_helper'

# This spec locks in the split behavior in create_test_model on macOS:
# ordinary examples should stay hermetic with a stubbed helper client,
# while real-environment examples must use the real helper client so they
# exercise the host's actual WiFi identity behavior.
RSpec.describe TestHelpers do
  include described_class

  let(:mac_os) { double('mac_os', id: :mac) }

  before do
    allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(mac_os)
  end

  it 'stubs the macOS helper client for ordinary tests' do
    model = create_test_model

    expect(model.send(:mac_helper_client)).to be_a(RSpec::Mocks::InstanceVerifyingDouble)
  end

  it 'uses the real macOS helper client when the example is real_env' do
    allow(self).to receive(:uses_real_env?).and_return(true)

    model = create_test_model

    expect(model.send(:mac_helper_client)).to be_a(WifiWand::MacOsWifiAuthHelper::Client)
  end
end
