# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/till_command'

describe WifiWand::TillCommand do
  let(:mock_model) { double('Model') }
  let(:cli) do
    double(
      'cli',
      model:            mock_model,
      interactive_mode: false,
      help_hint:        "Use 'wifi-wand help' or 'wifi-wand -h' for help."
    )
  end

  describe '#bind' do
    it 'returns a bound command with context-derived execution properties' do
      command = described_class.new
      bound_command = command.bind(cli)

      expect(bound_command).to be_a(described_class)
      expect(bound_command.metadata).to eq(command.metadata)
      expect(bound_command.model).to eq(mock_model)
      expect(bound_command.interactive_mode).to be(false)
    end
  end

  describe '#help_text' do
    it 'includes usage and states' do
      help = described_class.new.help_text

      expect(help).to include('Usage: wifi-wand till')
      expect(help).to include('wifi_on')
      expect(help).to include('internet_off')
    end
  end

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'calls model till method with target status' do
      expect(mock_model).to receive(:till).with(
        :wifi_on,
        timeout_in_secs:                         nil,
        wait_interval_in_secs:                   nil,
        stringify_permitted_values_in_error_msg: true
      )

      command.call('wifi_on')
    end

    it 'calls model till method with target status and wait interval' do
      expect(mock_model).to receive(:till).with(
        :internet_on,
        timeout_in_secs:                         2.5,
        wait_interval_in_secs:                   nil,
        stringify_permitted_values_in_error_msg: true
      )

      command.call('internet_on', '2.5')
    end

    it 'raises ConfigurationError when no arguments are provided' do
      expect { command.call }.to raise_error(WifiWand::ConfigurationError, /Missing target status argument/)
    end

    it 'raises ConfigurationError when first argument is nil' do
      expect { command.call(nil) }
        .to raise_error(WifiWand::ConfigurationError, /Missing target status argument/)
    end

    it 'raises ConfigurationError when timeout is not numeric' do
      expect { command.call('wifi_on', 'invalid') }
        .to raise_error(WifiWand::ConfigurationError, /Timeout must be a number/)
    end

    it 'raises ConfigurationError when interval is not numeric' do
      expect { command.call('wifi_on', '10', 'bad_value') }
        .to raise_error(WifiWand::ConfigurationError, /Interval must be a number/)
    end

    it 'raises ConfigurationError when timeout is negative' do
      expect { command.call('wifi_on', '-1') }
        .to raise_error(WifiWand::ConfigurationError, /Timeout must be non-negative/)
    end

    it 'raises ConfigurationError when interval is negative' do
      expect { command.call('wifi_on', '10', '-0.1') }
        .to raise_error(WifiWand::ConfigurationError, /Interval must be non-negative/)
    end

    it 'accepts valid numeric timeout and interval as strings' do
      expect(mock_model).to receive(:till).with(
        :wifi_off,
        timeout_in_secs:                         20.0,
        wait_interval_in_secs:                   0.5,
        stringify_permitted_values_in_error_msg: true
      )

      command.call('wifi_off', '20', '0.5')
    end
  end
end
