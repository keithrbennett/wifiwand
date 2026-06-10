# frozen_string_literal: true

require_relative('../../spec_helper')

load File.expand_path('../../../exe/wifi-wand', __dir__)

describe WifiWandExecutable do
  let(:argv) { ['info'] }
  let(:env) { { 'WIFIWAND_VERBOSE' => 'false' } }
  let(:in_stream) { StringIO.new }
  let(:out_stream) { StringIO.new }
  let(:err_stream) { StringIO.new }
  let(:options) { WifiWand::CommandLineOptions.new(verbose: false, interactive_mode: false, argv: argv) }
  let(:main) { instance_double(WifiWand::Main) }

  before do
    allow(WifiWand::Main).to receive(:new).and_return(main)
    allow(main).to receive(:call) do |&block|
      block.call(options)
      0
    end
  end

  describe '.call' do
    it 'exits with the status returned by run' do
      allow(described_class).to receive(:run).and_return(7)

      expect do
        described_class.call(argv: argv, env: env, in_stream: in_stream, out_stream: out_stream,
          err_stream: err_stream)
      end.to raise_error(SystemExit) { |error| expect(error.status).to eq(7) }
    end
  end

  describe '.run' do
    it 'delegates to the CLI main object and returns its exit code' do
      expect(WifiWand::Main)
        .to receive(:new)
        .with(out_stream, err_stream, argv: argv, env: env, in_stream: in_stream)
        .and_return(main)

      expect(described_class.run(argv: argv, env: env, in_stream: in_stream, out_stream: out_stream,
        err_stream: err_stream)).to eq(0)
    end

    it 'prints a clean interrupt message with command context and returns code 130' do
      allow(main).to receive(:call) do |&block|
        block.call(options)
        raise Interrupt
      end

      expect(described_class.run(argv: argv, env: env, in_stream: in_stream, out_stream: out_stream,
        err_stream: err_stream)).to eq(130)
      expect(err_stream.string).to eq("\nError: Interrupted by Ctrl-C while running command: info.\n")
    end

    it 'does not include command arguments in the interrupt context' do
      command_options = WifiWand::CommandLineOptions.new(
        verbose:          false,
        interactive_mode: false,
        argv:             ['connect', 'Cafe WiFi', 'secret-password']
      )
      allow(main).to receive(:call) do |&block|
        block.call(command_options)
        raise Interrupt
      end

      expect(described_class.run(argv: argv, env: env, in_stream: in_stream, out_stream: out_stream,
        err_stream: err_stream)).to eq(130)
      expect(err_stream.string).to eq("\nError: Interrupted by Ctrl-C while running command: connect.\n")
    end

    it 'prints one interrupt location in verbose mode without a full stack trace' do
      error = Interrupt.new
      allow(error).to receive(:backtrace).and_return(
        [
          '/usr/lib/ruby/kernel.rb:42:in `sleep`',
          '/home/user/project/lib/wifi_wand/models/base_model.rb:100:in `info`',
          '/home/user/project/lib/wifi_wand/main.rb:35:in `call`',
        ]
      )
      command_options = WifiWand::CommandLineOptions.new(
        verbose:          true,
        interactive_mode: false,
        argv:             ['info']
      )
      allow(main).to receive(:call) do |&block|
        block.call(command_options)
        raise error
      end

      expect(described_class.run(argv: argv, env: env, in_stream: in_stream, out_stream: out_stream,
        err_stream: err_stream)).to eq(130)
      expect(err_stream.string).to eq(
        "\nError: Interrupted by Ctrl-C while running command: info.\n" \
          "Interrupted at: /home/user/project/lib/wifi_wand/models/base_model.rb:100:in `info`\n"
      )
    end
  end
end
