# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OSFiltering do
  class HookCapturingConfigDouble
    attr_reader :before_each_hooks

    def initialize = @before_each_hooks = []

    def before(scope = :each, &block)
      raise ArgumentError, 'expected :each scope' unless scope == :each

      @before_each_hooks << block
    end
  end

  let(:config_double) { HookCapturingConfigDouble.new }

  around do |example|
    original_os_tag = defined?($compatible_os_tag) ? $compatible_os_tag : nil

    example.run

    $compatible_os_tag = original_os_tag
  end

  def configured_hook
    described_class.configure_os_filtering(config_double)
    config_double.before_each_hooks.fetch(0)
  end

  it 'skips real_env examples tagged for another OS' do
    $compatible_os_tag = :os_ubuntu

    example = instance_double(RSpec::Core::Example,
      metadata: { real_env: true, real_env_os: :os_mac })

    expect(self).to receive(:skip).with(/real_env/)
    instance_exec(example, &configured_hook)
  end

  it 'does not skip matching real_env examples on the current OS' do
    $compatible_os_tag = :os_ubuntu

    example = instance_double(RSpec::Core::Example,
      metadata: { real_env: true, real_env_os: :os_ubuntu })

    expect(self).not_to receive(:skip)
    instance_exec(example, &configured_hook)
  end

  it 'does not skip untagged examples' do
    $compatible_os_tag = :os_ubuntu

    example = instance_double(RSpec::Core::Example, metadata: {})

    expect(self).not_to receive(:skip)
    instance_exec(example, &configured_hook)
  end
end
