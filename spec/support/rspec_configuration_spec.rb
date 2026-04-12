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

  class HookConfigDouble
    attr_reader :before_hooks, :after_hooks

    def initialize
      @before_hooks = []
      @after_hooks = []
    end

    def before(*args, &block) = @before_hooks << [args, block]

    def after(*args, &block) = @after_hooks << [args, block]
  end

  let(:config_double) { PreflightConfigDouble.new }
  let(:basic_settings_config) { BasicSettingsConfigDouble.new }
  let(:hook_config) { HookConfigDouble.new }

  # Ensure we never leak OS state between examples. The real code relies on the
  # global $compatible_os_tag that OS filtering sets up; the examples need
  # stable values to exercise both branches.
  around do |example|
    original_os_tag = defined?($compatible_os_tag) ? $compatible_os_tag : nil

    example.run
  ensure
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
      double('example', metadata: { disruptive: true }),
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
      double('example', metadata: { disruptive: true, needs_sudo_access: true }),
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

  # This group tests the global `before` hook added by
  # `RSpecConfiguration.configure_test_stubbing`.
  #
  # On macOS, that hook installs stubs that stop ordinary specs from triggering
  # keychain lookups or `security find-generic-password` calls.
  #
  # This example checks the failure path: if installing those stubs breaks for
  # some unexpected reason, the hook should raise that error immediately instead
  # of hiding it and causing confusing follow-on failures in later specs.
  describe '.configure_test_stubbing' do
    let(:example) { double('example', metadata: {}) }
    let(:hook_block) { hook_config.before_hooks.first.last }

    before do
      $compatible_os_tag = :os_mac
      described_class.configure_test_stubbing(hook_config)
    end

    it 'fails loudly when stub installation raises an unexpected error' do
      allow(self).to receive(:allow_any_instance_of).and_raise(StandardError, 'stub failed')

      expect { instance_exec(example, &hook_block) }
        .to raise_error(StandardError, 'stub failed')
    end
  end

  describe '.configure_network_state_management' do
    before do
      described_class.configure_network_state_management(hook_config)
    end

    it 'restores state after each disruptive example without fail_silently' do
      after_each_hook = hook_config.after_hooks.find { |args, _block| args == %i[each disruptive] }

      expect(NetworkStateManager).to receive(:restore_state).with(fail_silently: false)
      after_each_hook.last.call
    end
  end

  describe '.attempt_final_network_restoration' do
    before do
      allow(described_class).to receive(:examples_to_run).and_return([
        double('example', metadata: { disruptive: true }),
      ])
      allow(NetworkStateManager).to receive(:network_state).and_return({ network_name: 'MyNetwork' })
    end

    it 'raises after printing a visible failure for expected restoration errors' do
      error = WifiWand::NetworkConnectionError.new('MyNetwork', 'timed out')
      allow(NetworkStateManager).to receive(:restore_state).with(fail_silently: false).and_raise(error)

      expect do
        described_class.attempt_final_network_restoration
      end.to output(
        /Could not restore network connection: Failed to connect to network 'MyNetwork': timed out/,
      ).to_stdout
        .and raise_error(WifiWand::NetworkConnectionError, /timed out/)
    end

    it 'propagates unexpected exceptions from final restoration' do
      allow(NetworkStateManager).to receive(:restore_state).with(fail_silently: false)
        .and_raise(NoMethodError, 'unexpected bug')

      expect do
        described_class.attempt_final_network_restoration
      end.to raise_error(NoMethodError, 'unexpected bug')
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
