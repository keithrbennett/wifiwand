# frozen_string_literal: true

RSpec.shared_context 'for command line interface tests' do
  include TestHelpers

  subject(:cli) { described_class.new(options) }

  let(:mock_model) { create_standard_mock_model }
  let(:mock_os) { create_mock_os_with_model(mock_model) }
  let(:options) { create_cli_options }
  let(:interactive_options) { create_cli_options(interactive_mode: true) }
  let(:interactive_cli) { described_class.new(interactive_options) }

  def invoke_command(cli, command_name, *args)
    cli.resolve_command(command_name).call(*args)
  end

  def invoke_help(cli, *args)
    WifiWand::HelpCommand.new.bind(cli).call(*args)
  end
  before do
    allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(mock_os)
  end
end

RSpec.shared_examples 'simple command delegation' do |command_name, model_method|
  it "calls model #{model_method} method" do
    expect(mock_model).to receive(model_method)
    silence_output { invoke_command(cli, command_name) }
  end
end

RSpec.shared_examples 'interactive vs non-interactive command' do |command_name, model_method, test_cases|
  context 'when in interactive mode' do
    it 'returns the result directly' do
      allow(interactive_cli.model).to receive(model_method).and_return(test_cases[:return_value])
      result = invoke_command(interactive_cli, command_name)
      expect(result).to eq(test_cases[:return_value])
    end
  end

  context 'when in non-interactive mode' do
    test_cases[:non_interactive_tests].each do |description, test_data|
      it description do
        allow(mock_model).to receive(model_method).and_return(test_data[:model_return])

        captured_output = silence_output do |stdout, _stderr|
          invoke_command(cli, command_name)
          stdout.string
        end

        if test_data[:expected_output].is_a?(Regexp)
          expect(captured_output).to match(test_data[:expected_output])
        else
          expect(captured_output).to eq(test_data[:expected_output])
        end
      end
    end
  end
end
