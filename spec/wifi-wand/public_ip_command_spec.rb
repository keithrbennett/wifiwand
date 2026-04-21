# frozen_string_literal: true

require 'json'
require_relative '../spec_helper'
require_relative '../../lib/wifi-wand/command_line_interface'

RSpec.describe 'public_ip command' do
  include TestHelpers

  let(:mock_model) { create_standard_mock_model }
  let(:mock_os) { create_mock_os_with_model(mock_model) }
  let(:options) { create_cli_options }
  let(:interactive_options) { create_cli_options(interactive_mode: true) }
  let(:cli) { WifiWand::CommandLineInterface.new(options) }
  let(:interactive_cli) { WifiWand::CommandLineInterface.new(interactive_options) }

  before do
    allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(mock_os)
    allow(cli).to receive(:run_shell)
    allow(interactive_cli).to receive(:run_shell)
  end

  it 'routes public_ip and pi through the command registry' do
    expect(cli.find_command_action('public_ip')).not_to be_nil
    expect(cli.find_command_action('pi')).not_to be_nil
    expect(cli.find_command_action('pu')).to be_nil
  end

  it 'uses both by default' do
    expect(mock_model).to receive(:public_ip_info).and_return('address' => '203.0.113.10', 'country' => 'TH')
    expect { cli.cmd_public_ip }.to output("Public IP Address: 203.0.113.10  Country: TH\n").to_stdout
  end

  {
    'address' => ['public_ip_address', 'Public IP Address: 203.0.113.10
', '203.0.113.10'],
    'country' => ['public_ip_country', 'Public IP Country: TH
', 'TH'],
    'both'    => ['public_ip_info', 'Public IP Address: 203.0.113.10  Country: TH
',
      { 'address' => '203.0.113.10', 'country' => 'TH' }],
    'a'       => ['public_ip_address', 'Public IP Address: 203.0.113.10
', '203.0.113.10'],
    'c'       => ['public_ip_country', 'Public IP Country: TH
', 'TH'],
    'b'       => ['public_ip_info', 'Public IP Address: 203.0.113.10  Country: TH
',
      { 'address' => '203.0.113.10', 'country' => 'TH' }],
  }.each do |selector, (method_name, output, interactive_value)|
    it "handles selector #{selector}" do
      return_value = interactive_value.is_a?(Hash) ? interactive_value : interactive_value.to_s
      allow(mock_model).to receive(method_name).and_return(return_value)
      expect { cli.cmd_public_ip(selector) }.to output(output).to_stdout
    end

    it "returns machine-readable data for selector #{selector} in interactive mode" do
      return_value = interactive_value.is_a?(Hash) ? interactive_value : interactive_value.to_s
      allow(interactive_cli.model).to receive(method_name).and_return(return_value)
      expect(interactive_cli.cmd_public_ip(selector)).to eq(return_value)
    end
  end

  it 'supports machine-readable JSON output for both' do
    json_cli = WifiWand::CommandLineInterface.new(create_cli_options(
      post_processor: ->(object) { JSON.generate(object) }
    ))
    allow(json_cli.model).to receive(:public_ip_info).and_return('address' => '203.0.113.10',
      'country' => 'TH')

    expect { json_cli.cmd_public_ip('both') }
      .to output(%({"address":"203.0.113.10","country":"TH"}
)).to_stdout
  end

  it 'raises a clear error for invalid selectors' do
    expect { cli.cmd_public_ip('x') }.to raise_error(
      WifiWand::ConfigurationError,
      "Invalid selector 'x'. Use one of: address (a), country (c), both (b)."
    )
  end

  it 'passes selector arguments through process_command_line for the pi alias' do
    alias_cli = WifiWand::CommandLineInterface.new(options, argv: %w[pi a])
    expect(alias_cli.model).to receive(:public_ip_address).and_return('203.0.113.10')

    expect { alias_cli.process_command_line }.to output("Public IP Address: 203.0.113.10\n").to_stdout
  end

  it 'prints command-specific help for public_ip' do
    expect { cli.cmd_h('public_ip') }.to output(/Usage: wifi-wand public_ip/).to_stdout
  end

  it 'returns command help text for the public_ip alias' do
    command = cli.resolve_command('pi')

    expect(command).to be_a(WifiWand::PublicIpCommand)
    expect(command.help_text).to include('Usage: wifi-wand public_ip')
    expect(command.help_text).to include('address (a)')
  end
end
