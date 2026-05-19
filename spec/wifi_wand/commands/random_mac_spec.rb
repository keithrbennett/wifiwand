# frozen_string_literal: true

require 'json'
require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/command_line_interface'

RSpec.describe 'random_mac command' do
  include TestHelpers

  let(:mock_model) { create_standard_mock_model }
  let(:mock_os) { create_mock_os_with_model(mock_model) }
  let(:options) { create_cli_options }
  let(:cli) { WifiWand::CommandLineInterface.new(options) }

  def invoke_command(command_line_interface, command_name, *args)
    command_line_interface.resolve_command(command_name).call(*args)
  end

  before do
    allow(WifiWand::Platforms::Selector).to receive(:current_os).and_return(mock_os)
    allow(cli).to receive(:run_shell)
  end

  it 'routes random_mac and rmac through the command registry' do
    expect(cli.find_command_action('random_mac')).not_to be_nil
    expect(cli.find_command_action('rmac')).not_to be_nil
    expect(cli.find_command_action('rm')).to be_nil
    expect(cli.find_command_action('random')).to be_nil
  end

  it 'prints a random MAC address' do
    expect(mock_model).to receive(:random_mac_address).and_return('02:11:22:33:44:55')

    expect { invoke_command(cli, 'random_mac') }
      .to output("02:11:22:33:44:55\n").to_stdout
  end

  it 'supports machine-readable JSON output' do
    json_cli = WifiWand::CommandLineInterface.new(create_cli_options(
      post_processor: ->(object) { JSON.generate(object) }
    ))
    allow(WifiWand::Platforms::Selector).to receive(:current_os).and_return(mock_os)
    allow(json_cli.model).to receive(:random_mac_address).and_return('02:11:22:33:44:55')

    expect { invoke_command(json_cli, 'rmac') }
      .to output(%("02:11:22:33:44:55"\n)).to_stdout
  end

  it 'raises a usage-oriented error when extra arguments are provided' do
    expect(mock_model).not_to receive(:random_mac_address)

    expect { invoke_command(cli, 'random_mac', 'extra') }
      .to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('Unexpected argument(s): extra')
        expect(error.message).to include('Usage: wifi-wand random_mac')
        expect(error.message).to include("Use 'wifi-wand help' or 'wifi-wand -h' for help.")
      }
  end

  it 'prints command-specific help' do
    expect { invoke_command(cli, 'help', 'random_mac') }
      .to output(/Usage: wifi-wand random_mac/).to_stdout
  end
end
