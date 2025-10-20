# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RSpecConfiguration do
  # Minimal stand-in for the RSpec configuration object. We only need to
  # capture the before(:suite) blocks so they can be triggered manually in the
  # examples, which keeps the tests close to the real preflight flow.
  class PreflightConfigDouble
    attr_reader :suite_hooks

    def initialize
      @suite_hooks = []
    end

    def before(scope, &block)
      raise ArgumentError, 'expected :suite scope' unless scope == :suite

      @suite_hooks << block
    end
  end

  let(:config_double) { PreflightConfigDouble.new }

  # Ensure we never leak CI or OS state between examples. The real code treats
  # CI as a hard skip for preflight work and relies on the global
  # $compatible_os_tag that OS filtering sets up; the examples need stable
  # values to exercise both branches.
  around do |example|
    original_ci = ENV.delete('CI')
    original_os_tag = defined?($compatible_os_tag) ? $compatible_os_tag : nil

    example.run

    if original_ci
      ENV['CI'] = original_ci
    else
      ENV.delete('CI')
    end

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

  # Ubuntu (and other Linux hosts) do not require sudo/keychain prompts, but
  # they still depend on network state capture to restore connectivity after
  # disruptive specs. This example fails if the capture hook stops running
  # outside the macOS path, so we get an early warning if it regresses.
  it 'captures network state when disruptive tests run on non-macOS hosts' do
    $compatible_os_tag = :os_ubuntu

    allow(described_class).to receive(:get_examples_to_run).and_return([
      double('example', metadata: { disruptive: true })
    ])

    expect(described_class).to receive(:handle_network_state_capture).with(true)
    run_preflight
  end

  # macOS still needs the original authentication steps, and we only want to
  # issue the network capture once for the suite. This ensures the refactor did
  # not introduce duplicate calls and that the sudo/keychain paths remain gated
  # behind macOS detection.
  it 'captures network state exactly once when disruptive auth tests run on macOS' do
    $compatible_os_tag = :os_mac

    allow(described_class).to receive(:get_examples_to_run).and_return([
      double('example', metadata: { disruptive: true, needs_sudo_access: true })
    ])

    expect(described_class).to receive(:handle_network_state_capture).with(true).once
    expect(described_class).to receive(:handle_sudo_preflight).with(true).and_return(nil)
    expect(described_class).to receive(:handle_keychain_preflight).with(true).and_return(nil)

    run_preflight
  end
end
