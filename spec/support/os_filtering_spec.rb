# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OSFiltering do
  class HookCapturingConfigDouble
    attr_reader :before_each_hooks

    def initialize = @before_each_hooks = []

    def before(scope, &block)
      raise ArgumentError, 'expected :each scope' unless scope == :each

      @before_each_hooks << block
    end
  end

  let(:config_double) { HookCapturingConfigDouble.new }

  around do |example|
    original_os_tag = defined?($compatible_os_tag) ? $compatible_os_tag : nil
    original_compatible_disruptive_tag = defined?($compatible_disruptive_tag) ? $compatible_disruptive_tag : nil
    original_incompatible_disruptive_tags = defined?($incompatible_disruptive_tags) ? $incompatible_disruptive_tags : nil

    example.run

    $compatible_os_tag = original_os_tag
    $compatible_disruptive_tag = original_compatible_disruptive_tag
    $incompatible_disruptive_tags = original_incompatible_disruptive_tags
  end

  def configured_hook
    described_class.configure_os_filtering(config_double)
    config_double.before_each_hooks.fetch(0)
  end

  it 'skips disruptive_mac examples on ubuntu hosts' do
    $compatible_os_tag = :os_ubuntu
    $incompatible_disruptive_tags = [:disruptive_mac]

    example = instance_double(RSpec::Core::Example, metadata: { disruptive_mac: true })

    expect(self).to receive(:skip).with(/disruptive_mac/)
    instance_exec(example, &configured_hook)
  end

  it 'does not skip matching disruptive_ubuntu examples on ubuntu hosts' do
    $compatible_os_tag = :os_ubuntu
    $incompatible_disruptive_tags = [:disruptive_mac]

    example = instance_double(RSpec::Core::Example, metadata: { disruptive_ubuntu: true })

    expect(self).not_to receive(:skip)
    instance_exec(example, &configured_hook)
  end

  it 'does not skip untagged examples' do
    $compatible_os_tag = :os_ubuntu
    $incompatible_disruptive_tags = [:disruptive_mac]

    example = instance_double(RSpec::Core::Example, metadata: {})

    expect(self).not_to receive(:skip)
    instance_exec(example, &configured_hook)
  end
end
