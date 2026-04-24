# frozen_string_literal: true

require 'rbconfig'
require 'tempfile'
require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/command_executor'

describe WifiWand::CommandExecutor do
  def wait_for_file_contents(path, timeout: 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      contents = File.read(path)
      return contents unless contents.empty?

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise "Timeout waiting for contents in #{path}"
      end

      sleep 0.05
    end
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def wait_for_process_exit(pid, timeout: 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      return unless process_alive?(pid)

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise "Timeout waiting for process #{pid} to exit"
      end

      sleep 0.05
    end
  end

  describe '#run_os_command' do
    context 'with verbose mode disabled' do
      let(:executor) { described_class.new(verbose: false) }

      it 'executes commands successfully' do
        result = executor.run_os_command(%w[echo test])
        expect(result).to be_a(WifiWand::CommandExecutor::OsCommandResult)
        expect(result.stdout.strip).to eq('test')
      end

      it 'supports timeouts for array commands without changing successful behavior' do
        result = executor.run_os_command(
          [RbConfig.ruby, '-e', 'sleep 0.05; print "ok"'],
          true,
          timeout_in_secs: 1
        )

        expect(result.stdout).to eq('ok')
        expect(result.exitstatus).to eq(0)
      end

      it 'raises OsCommandError on command failure when raise_on_error is true' do
        expect do
          executor.run_os_command(['false'])
        end.to raise_error(WifiWand::CommandExecutor::OsCommandError)
      end

      it 'returns result without raising on command failure when raise_on_error is false' do
        result = executor.run_os_command(['false'], false)
        expect(result).to be_a(WifiWand::CommandExecutor::OsCommandResult)
        expect(result.exitstatus).not_to eq(0)
      end

      it 'raises ArgumentError when run_os_command receives a String' do
        expect do
          executor.run_os_command('echo "test"')
        end.to raise_error(ArgumentError, /run_os_command requires an Array/)
      end

      it 'raises ArgumentError when run_repl_command receives a non-String' do
        expect do
          executor.run_repl_command(%w[echo test])
        end.to raise_error(ArgumentError, /run_repl_command requires a String/)
      end

      it 'terminates timed out child processes without leaking them' do
        Tempfile.create('wifiwand-command-timeout') do |pid_file|
          pid_file.close
          command = [
            RbConfig.ruby,
            '-e',
            "File.write(ARGV[0], Process.pid.to_s); Signal.trap('TERM', 'IGNORE'); sleep 30",
            pid_file.path,
          ]

          expect do
            executor.run_os_command(command, true, timeout_in_secs: 0.2)
          end.to raise_error(WifiWand::CommandTimeoutError)

          pid = wait_for_file_contents(pid_file.path).to_i
          wait_for_process_exit(pid)
          expect(process_alive?(pid)).to be(false)
        end
      end

      it 'terminates descendant processes created by a timed out command' do
        Tempfile.create('wifiwand-command-timeout-descendant') do |pid_file|
          pid_file.close
          command = [
            RbConfig.ruby,
            '-e',
            <<~RUBY,
              child_pid = Process.spawn(ARGV[1], '-e', 'Signal.trap("TERM", "IGNORE"); sleep 30')
              File.write(ARGV[0], child_pid.to_s)
              sleep 30
            RUBY
            pid_file.path,
            RbConfig.ruby,
          ]

          expect do
            executor.run_os_command(command, true, timeout_in_secs: 0.2)
          end.to raise_error(WifiWand::CommandTimeoutError)

          descendant_pid = wait_for_file_contents(pid_file.path).to_i
          wait_for_process_exit(descendant_pid)
          expect(process_alive?(descendant_pid)).to be(false)
        end
      end

      it 'raises CommandNotFoundError when an array command executable is missing' do
        expect do
          executor.run_os_command(['nonexistent_command_12345'])
        end.to raise_error(WifiWand::CommandNotFoundError, /nonexistent_command_12345/)
      end

      it 'treats stream closure IOError as normal command shutdown' do
        stream_class = Struct.new(:responses) do
          def readpartial(_size)
            response = responses.shift
            raise response if response.is_a?(Exception)

            response
          end
        end

        stdin = instance_double(IO, close: nil)
        stdout = stream_class.new(['partial output', IOError.new('stream closed in another thread')])
        stderr = stream_class.new([EOFError.new])
        wait_thr = instance_double(Thread)
        status = instance_double(Process::Status, exitstatus: 0)

        allow(wait_thr).to receive_messages(join: wait_thr, value: status)
        allow(Open3).to receive(:popen3).and_yield(stdin, stdout, stderr, wait_thr)

        result = executor.run_os_command(%w[echo test])

        expect(result.stdout).to eq('partial output')
        expect(result.stderr).to eq('')
        expect(result.exitstatus).to eq(0)
      end
    end

    context 'with REPL string commands' do
      let(:executor) { described_class.new(verbose: false) }

      it 'captures both stdout and stderr' do
        result = executor.run_repl_command("bash -c 'echo \"stdout\"; echo \"stderr\" >&2'", false)
        expect(result.stdout).to include('stdout')
        expect(result.stderr).to include('stderr')
      end

      it 'raises CommandTimeoutError for shell commands that exceed the timeout' do
        expect do
          executor.run_repl_command("#{RbConfig.ruby} -e 'sleep 5'", true, timeout_in_secs: 0.2)
        end.to raise_error(WifiWand::CommandTimeoutError, /sleep 5/)
      end
    end

    context 'with verbose mode enabled' do
      let(:executor) { described_class.new(verbose: true) }

      it 'outputs command attempt and duration info' do
        expect do
          executor.run_repl_command('echo "test"')
        end.to output(/Command:.*echo "test".*Duration:.*seconds/m).to_stdout
      end
    end
  end

  describe '#try_os_command_until' do
    let(:executor) { described_class.new(verbose: false) }

    it 'returns output when condition is met on first try' do
      condition = ->(output) { output.include?('success') }
      expect(executor.try_os_command_until(%w[echo success], condition, 3).strip).to eq('success')
    end

    it 'retries until condition is met' do
      call_count = 0

      allow(executor).to receive(:run_os_command) do |command|
        call_count += 1
        WifiWand::CommandExecutor::OsCommandResult.new(
          stdout:          "attempt #{call_count}",
          stderr:          '',
          combined_output: "attempt #{call_count}",
          exitstatus:      0,
          command:         command,
          duration:        0.0
        )
      end

      condition = ->(output) { output.include?('attempt 2') }

      result = executor.try_os_command_until(%w[echo test], condition, 5)
      expect(result.strip).to eq('attempt 2')
      expect(call_count).to eq(2)
    end

    it 'returns nil when max_tries is reached without success' do
      condition = ->(_output) { false }
      expect(executor.try_os_command_until(%w[echo fail], condition, 2)).to be_nil
    end

    it 'reports attempt count in verbose mode' do
      io = StringIO.new
      verbose_executor = described_class.new(verbose: true, output: io)
      condition = ->(_output) { true }
      verbose_executor.try_os_command_until(%w[echo test], condition, 3)
      expect(io.string).to match(/Command was executed 1 time/)
    end
  end

  describe '#command_available?' do
    let(:executor) { described_class.new(verbose: false) }

    it 'returns true for available commands' do
      expect(executor.command_available?('echo')).to be true
    end

    it 'returns false for unavailable commands' do
      expect(executor.command_available?('nonexistent_command_12345')).to be false
    end

    it 'checks executable files in PATH directories' do
      allow(ENV).to receive(:[]).with('PATH').and_return('/usr/bin:/bin')
      allow(File).to receive_messages(executable?: false, directory?: false)
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
    let(:error) { described_class.new(exitstatus: 1, command: 'false', text: 'command failed') }

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
        command:    'false',
        text:       'command failed',
      })
    end
  end

  describe 'integration with BaseModel' do
    it 'is accessible through BaseModel' do
      require_relative '../../../lib/wifi-wand/models/base_model'
      require 'ostruct'

      expect do
        WifiWand::BaseModel.new(OpenStruct.new(verbose: false))
      end.not_to raise_error
    end
  end
end
