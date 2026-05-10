# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/on_command'
require_relative '../../../lib/wifi_wand/commands/off_command'
require_relative '../../../lib/wifi_wand/commands/cycle_command'
require_relative '../../../lib/wifi_wand/commands/disconnect_command'

RSpec.describe 'basic WiFi commands' do
  [
    {
      command_class: WifiWand::OnCommand,
      model_method:  :wifi_on,
      usage:         'Usage: wifi-wand on',
      description:   'turn WiFi on',
    },
    {
      command_class: WifiWand::OffCommand,
      model_method:  :wifi_off,
      usage:         'Usage: wifi-wand off',
      description:   'turn WiFi off',
    },
    {
      command_class: WifiWand::CycleCommand,
      model_method:  :cycle_network,
      usage:         'Usage: wifi-wand cycle',
      description:   'cycle WiFi off and back on',
    },
    {
      command_class: WifiWand::DisconnectCommand,
      model_method:  :disconnect,
      usage:         'Usage: wifi-wand disconnect',
      description:   'disconnect from the current WiFi network without turning WiFi off',
    },
  ].each do |command_case|
    describe command_case[:command_class] do
      let(:mock_model) { double('model') }
      let(:cli) do
        double('cli', model: mock_model, help_hint: "Use 'wifi-wand help' or 'wifi-wand -h' for help.")
      end

      it_behaves_like 'binds command context', bound_attributes: { model: :mock_model }

      it_behaves_like 'has default command help text',
        usage:       command_case[:usage],
        description: command_case[:description]

      describe '#call' do
        subject(:command) { described_class.new.bind(cli) }

        it "delegates to model.#{command_case[:model_method]}" do
          expect(mock_model).to receive(command_case[:model_method])

          command.call
        end

        it 'raises a usage-oriented error when extra arguments are provided' do
          expect(mock_model).not_to receive(command_case[:model_method])

          expect { command.call('extra') }
            .to raise_error(WifiWand::ConfigurationError) { |error|
              expect(error.message).to include('Unexpected argument(s): extra')
              expect(error.message).to include(command_case[:usage])
              expect(error.message).to include("Use 'wifi-wand help' or 'wifi-wand -h' for help.")
            }
        end
      end
    end
  end
end
