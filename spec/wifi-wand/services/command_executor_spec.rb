# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/command_executor'

describe WifiWand::CommandExecutor do

  describe '#run_os_command' do
    context 'with verbose mode disabled' do
      let(:executor) { WifiWand::CommandExecutor.new(verbose: false) }

      it 'executes commands successfully' do
        result = executor.run_os_command('echo "test"')
        expect(result).to be_a(WifiWand::CommandExecutor::OsCommandResult)
        expect(result.stdout.strip).to eq('test')
      end

      it 'raises OsCommandError on command failure when raise_on_error is true' do
        expect {
          executor.run_os_command('false')  # Command that always fails
        }.to raise_error(WifiWand::CommandExecutor::OsCommandError)
      end

      it 'returns result without raising on command failure when raise_on_error is false' do
        result = executor.run_os_command('false', false)
        expect(result).to be_a(WifiWand::CommandExecutor::OsCommandResult)
        expect(result.exitstatus).not_to eq(0)
      end

      it 'captures both stdout and stderr' do
        result = executor.run_os_command('bash -c \'echo "stdout"; echo "stderr" >&2\'', false)
        expect(result.stdout).to include('stdout')
        expect(result.stderr).to include('stderr')
      end
    end

    context 'with verbose mode enabled' do
      let(:executor) { WifiWand::CommandExecutor.new(verbose: true) }

      it 'outputs command attempt and duration info' do
        expect {
          executor.run_os_command('echo "test"')
        }.to output(/Command:.*echo "test".*Duration:.*seconds/m).to_stdout
      end
    end
  end

  describe '#try_os_command_until' do
    let(:executor) { WifiWand::CommandExecutor.new(verbose: false) }

    it 'returns output when condition is met on first try' do
      condition = ->(output) { output.include?('success') }
      expect(executor.try_os_command_until('echo "success"', condition, 3).strip).to eq('success')
    end

    it 'retries until condition is met' do
      call_count = 0
      
      # Mock the run_os_command to include the iteration number in output
      allow(executor).to receive(:run_os_command) do |command|
        call_count += 1
        WifiWand::CommandExecutor::OsCommandResult.new(
          stdout: "attempt #{call_count}",
          stderr: '',
          combined_output: "attempt #{call_count}",
          exitstatus: 0,
          command: command,
          duration: 0.0
        )
      end

      condition = ->(output) { 
        # Succeed on second try
        output.include?('attempt 2')
      }

      result = executor.try_os_command_until('echo "test"', condition, 5)
      expect(result.strip).to eq('attempt 2')  # Should succeed on second try
      expect(call_count).to eq(2)  # Should have been called exactly twice
    end

    it 'returns nil when max_tries is reached without success' do
      condition = ->(_output) { false }  # Never succeeds
      expect(executor.try_os_command_until('echo "fail"', condition, 2)).to be_nil
    end

    it 'reports attempt count in verbose mode' do
      io = StringIO.new
      verbose_executor = WifiWand::CommandExecutor.new(verbose: true, output: io)
      condition = ->(_output) { true }  # Succeeds on first try
      verbose_executor.try_os_command_until('echo "test"', condition, 3)
      expect(io.string).to match(/Command was executed 1 time/)
    end
  end

  describe '#command_available?' do
    let(:executor) { WifiWand::CommandExecutor.new(verbose: false) }

    it 'returns true for available commands' do
      expect(executor.command_available?('echo')).to be true
    end

    it 'returns false for unavailable commands' do
      expect(executor.command_available?('nonexistent_command_12345')).to be false
    end

    it 'checks executable files in PATH directories' do
      # Mock ENV['PATH'] to test the implementation
      allow(ENV).to receive(:[]).with('PATH').and_return('/usr/bin:/bin')
      allow(File).to receive(:executable?).and_return(false)
      allow(File).to receive(:directory?).and_return(false)
      allow(File).to receive(:executable?).with('/usr/bin/test_cmd').and_return(true)

      expect(executor.command_available?('test_cmd')).to be true
    end

    it 'excludes directories even if marked executable' do
      allow(ENV).to receive(:[]).with('PATH').and_return('/usr/bin')
      allow(File).to receive(:executable?).with('/usr/bin/test_dir').and_return(true)
      allow(File).to receive(:directory?).with('/usr/bin/test_dir').and_return(true)

      expect(executor.command_available?('test_dir')).to be false
    end
  end

  describe WifiWand::CommandExecutor::OsCommandError do
    let(:error) { WifiWand::CommandExecutor::OsCommandError.new(1, 'false', 'command failed') }

    it 'stores command execution details' do
      expect(error.exitstatus).to eq(1)
      expect(error.command).to eq('false')
      expect(error.text).to eq('command failed')
      expect(error.result).to be_a(WifiWand::CommandExecutor::OsCommandResult)
      expect(error.result.combined_output).to eq('command failed')
    end

    it 'provides readable string representation' do
      error_string = error.to_s
      expect(error_string).to include('Error code 1')
      expect(error_string).to include('command = false')
      expect(error_string).to include('text = command failed')
    end

    it 'provides hash representation' do
      error_hash = error.to_h
      expect(error_hash).to eq({
        exitstatus: 1,
        command: 'false',
        text: 'command failed'
      })
    end
  end

  describe 'integration with BaseModel' do
    # Test that the service integrates properly with BaseModel
    it 'is accessible through BaseModel' do
      require_relative '../../../lib/wifi-wand/models/base_model'
      require 'ostruct'
      
      # This tests the integration without actually running OS-specific code
      expect {
        WifiWand::BaseModel.new(OpenStruct.new(verbose: false))
      }.not_to raise_error
    end

  end
end
