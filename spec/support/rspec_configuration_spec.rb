# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RSpecConfiguration do
  class BasicSettingsConfigDouble
    attr_reader :derived_metadata_blocks

    def initialize = @derived_metadata_blocks = []

    def example_status_persistence_file_path=(_path)
    end

    def filter_run_including(*_args) = nil

    def run_all_when_everything_filtered=(_value)
    end

    def only_failures? = false

    def filter_run_excluding(*_args) = nil

    def before(*_args) = nil

    def after(*_args) = nil

    def include(_module) = nil

    def register_ordering(*_args) = nil

    def order=(_value)
    end

    def define_derived_metadata(&block) = @derived_metadata_blocks << block
  end

  # Minimal stand-in for the RSpec configuration object. We only need to
  # capture the before(:suite) blocks so they can be triggered manually in the
  # examples, which keeps the tests close to the real preflight flow.
  class PreflightConfigDouble
    attr_reader :suite_hooks

    def initialize = @suite_hooks = []

    def before(scope, &block)
      raise ArgumentError, 'expected :suite scope' unless scope == :suite

      @suite_hooks << block
    end
  end

  let(:config_double) { PreflightConfigDouble.new }
  let(:basic_settings_config) { BasicSettingsConfigDouble.new }

  # Ensure we never leak OS state between examples. The real code relies on the
  # global $compatible_os_tag that OS filtering sets up; the examples need
  # stable values to exercise both branches.
  around do |example|
    original_os_tag = defined?($compatible_os_tag) ? $compatible_os_tag : nil

    example.run

    $compatible_os_tag = original_os_tag
  end

  # Helper to mirror the real configure-preflight hook and immediately execute
  # the captured before(:suite) callbacks. This keeps the expectations focused
  # on the side effects (which helper methods get called) instead of the hook
  # plumbing itself.
  def run_preflight
    described_class.configure_preflight_authentication(config_double)
    config_double.suite_hooks.each(&:call)
  end

  def apply_derived_metadata(metadata)
    described_class.send(:configure_basic_settings, basic_settings_config)
    basic_settings_config.derived_metadata_blocks.each { |block| block.call(metadata) }
    metadata
  end

  # Ubuntu (and other Linux hosts) do not require sudo/keychain prompts, but
  # they still depend on network state capture to restore connectivity after
  # disruptive specs. This example fails if the capture hook stops running
  # outside the macOS path, so we get an early warning if it regresses.
  it 'captures network state when disruptive tests run on non-macOS hosts' do
    $compatible_os_tag = :os_ubuntu

    allow(described_class).to receive(:examples_to_run).and_return([
      double('example', metadata: { disruptive: true })
    ])

    expect(described_class).to receive(:handle_network_state_capture).with(true)
    run_preflight
  end

  # macOS still needs the original authentication steps, and we only want to
  # issue the network capture once for the suite. This ensures the refactor did
  # not introduce duplicate calls and that the sudo path remains gated
  # behind macOS detection.
  it 'captures network state exactly once when disruptive auth tests run on macOS' do
    $compatible_os_tag = :os_mac

    allow(described_class).to receive(:examples_to_run).and_return([
      double('example', metadata: { disruptive: true, needs_sudo_access: true })
    ])

    expect(described_class).to receive(:handle_network_state_capture).with(true).once
    expect(described_class).to receive(:handle_sudo_preflight).with(true).and_return(nil)

    run_preflight
  end

  describe '.handle_network_state_capture' do
    let(:mock_model) { double('model') }

    before do
      allow(NetworkStateManager).to receive(:model).and_return(mock_model)
    end

    it 'does nothing when no disruptive tests will run' do
      expect(mock_model).not_to receive(:connected?)
      described_class.handle_network_state_capture(false)
    end

    it 'raises when not connected to a network' do
      allow(mock_model).to receive(:connected?).and_return(false)

      expect { described_class.handle_network_state_capture(true) }
        .to raise_error(RuntimeError, /active network connection/)
    end

    it 'raises when connected but captured state has no network name' do
      allow(mock_model).to receive(:connected?).and_return(true)
      allow(NetworkStateManager).to receive(:capture_state)
      allow(NetworkStateManager).to receive(:network_state).and_return({ network_name: nil })

      expect { described_class.handle_network_state_capture(true) }
        .to raise_error(RuntimeError, /restorable network state/)
    end

    it 'succeeds when connected and network name is captured' do
      allow(mock_model).to receive(:connected?).and_return(true)
      allow(NetworkStateManager).to receive(:capture_state)
      allow(NetworkStateManager).to receive(:network_state).and_return({ network_name: 'MyNetwork' })

      expect { described_class.handle_network_state_capture(true) }.not_to raise_error
    end
  end

  it 'marks disruptive_mac examples as disruptive and slow' do
    metadata = apply_derived_metadata(disruptive_mac: true)

    expect(metadata[:disruptive]).to be(true)
    expect(metadata[:slow]).to be(true)
  end

  it 'marks disruptive_ubuntu examples as disruptive and slow' do
    metadata = apply_derived_metadata(disruptive_ubuntu: true)

    expect(metadata[:disruptive]).to be(true)
    expect(metadata[:slow]).to be(true)
  end

  it 'leaves non-disruptive examples unchanged' do
    metadata = apply_derived_metadata({})

    expect(metadata).not_to have_key(:disruptive)
    expect(metadata).not_to have_key(:slow)
  end
end
