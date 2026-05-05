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

  def inherited_pipe_command(pid_file)
    [
      'sh',
      '-c',
      <<~SH,
        sh -c 'sleep 30' &
        child_pid=$!
        printf '%s' "$child_pid" > "$1"
        printf 'parent done\\n'
      SH
      'sh',
      pid_file.path,
    ]
  end

  def terminate_pid_from_file(pid_file)
    return if File.empty?(pid_file.path)

    pid = File.read(pid_file.path).to_i
    return unless process_alive?(pid)

    Process.kill('KILL', pid)
    wait_for_process_exit(pid)
  end

  def run_command_in_thread(executor, command, deadline: 3)
    runner = Thread.new { executor.run_command_using_args(command, raise_on_error: false) }
    runner.report_on_exception = false
    joined = runner.join(deadline)
    raise "Command did not finish within #{deadline} second(s)" unless joined

    runner.value
  ensure
    runner&.kill if runner&.alive?
  end

  describe '#run_command_using_args' do
    context 'with verbose mode disabled' do
      let(:executor) { described_class.new(verbose: false) }
      let(:stream_class) do
        Struct.new(:responses) do
          def readpartial(_size)
            response = responses.shift
            raise response if response.is_a?(Exception)

            response
          end
        end
      end

      it 'executes commands successfully' do
        result = executor.run_command_using_args(%w[echo test])
        expect(result).to be_a(WifiWand::CommandExecutor::OsCommandResult)
        expect(result.stdout.strip).to eq('test')
      end

      it 'supports timeouts for array commands without changing successful behavior' do
        result = executor.run_command_using_args(
          ['sh', '-c', 'sleep 0.05; printf ok'],
          raise_on_error:  true,
          timeout_in_secs: 3
        )

        expect(result.stdout).to eq('ok')
        expect(result.exitstatus).to eq(0)
      end

      it 'raises OsCommandError on command failure when raise_on_error is true' do
        expect do
          executor.run_command_using_args(['false'])
        end.to raise_error(WifiWand::CommandExecutor::OsCommandError)
      end

      it 'returns result without raising on command failure when raise_on_error is false' do
        result = executor.run_command_using_args(['false'], raise_on_error: false)
        expect(result).to be_a(WifiWand::CommandExecutor::OsCommandResult)
        expect(result.exitstatus).not_to eq(0)
      end

      it 'raises ArgumentError when run_command_using_args receives a String' do
        expect do
          executor.run_command_using_args('echo "test"')
        end.to raise_error(ArgumentError, /run_command_using_args requires an Array/)
      end

      it 'raises ArgumentError when run_command_using_shell receives a non-String' do
        expect do
          executor.run_command_using_shell(%w[echo test])
        end.to raise_error(ArgumentError, /run_command_using_shell requires a String/)
      end

      it 'terminates timed out child processes without leaking them' do
        Tempfile.create('wifiwand-command-timeout') do |pid_file|
          pid_file.close
          command = [
            'sh',
            '-c',
            "printf '%s' $$ > \"$1\"; trap '' TERM; sleep 30",
            'sh',
            pid_file.path,
          ]

          expect { executor.run_command_using_args(command, raise_on_error: true, timeout_in_secs: 1) }
            .to raise_error(WifiWand::CommandTimeoutError)

          pid = wait_for_file_contents(pid_file.path).to_i
          wait_for_process_exit(pid)
          expect(process_alive?(pid)).to be(false)
        end
      end

      it 'terminates descendant processes created by a timed out command' do
        Tempfile.create('wifiwand-command-timeout-descendant') do |pid_file|
          pid_file.close
          command = [
            'sh',
            '-c',
            <<~SH,
              sh -c 'trap "" TERM; sleep 30' &
              child_pid=$!
              printf '%s' "$child_pid" > "$1"
              sleep 30
            SH
            'sh',
            pid_file.path,
          ]

          expect { executor.run_command_using_args(command, raise_on_error: true, timeout_in_secs: 1) }
            .to raise_error(WifiWand::CommandTimeoutError)

          descendant_pid = wait_for_file_contents(pid_file.path).to_i
          wait_for_process_exit(descendant_pid)
          expect(process_alive?(descendant_pid)).to be(false)
        end
      end

      it 'does not hang when a descendant keeps inherited output pipes open' do
        Tempfile.create('wifiwand-command-inherited-pipes') do |pid_file|
          pid_file.close

          result = run_command_in_thread(executor, inherited_pipe_command(pid_file))

          expect(result.stdout).to include('parent done')
          expect(result.exitstatus).to eq(0)
        ensure
          terminate_pid_from_file(pid_file)
        end
      end

      it 'raises CommandNotFoundError when an array command executable is missing' do
        expect do
          executor.run_command_using_args(['nonexistent_command_12345'])
        end.to raise_error(WifiWand::CommandNotFoundError, /nonexistent_command_12345/)
      end

      it 'treats stream closure IOError as normal command shutdown' do
        stdin = instance_double(IO, close: nil)
        stdout = stream_class.new(['partial output', IOError.new('stream closed in another thread')])
        stderr = stream_class.new([EOFError.new])
        wait_thr = instance_double(Thread)
        status = instance_double(Process::Status, exitstatus: 0, termsig: nil)

        allow(wait_thr).to receive_messages(join: wait_thr, value: status)
        allow(Open3).to receive(:popen3).and_yield(stdin, stdout, stderr, wait_thr)

        result = executor.run_command_using_args(%w[echo test])

        expect(result.stdout).to eq('partial output')
        expect(result.stderr).to eq('')
        expect(result.exitstatus).to eq(0)
      end

      it 'represents commands terminated by a signal as unsuccessful results' do
        stdin = instance_double(IO, close: nil)
        stdout = stream_class.new([EOFError.new])
        stderr = stream_class.new(['aborted', EOFError.new])
        wait_thr = instance_double(Thread)
        status = instance_double(Process::Status, exitstatus: nil, termsig: 6)

        allow(wait_thr).to receive_messages(join: wait_thr, value: status)
        allow(Open3).to receive(:popen3).and_yield(stdin, stdout, stderr, wait_thr)

        result = executor.run_command_using_args(%w[nmcli radio wifi], raise_on_error: false)

        expect(result).not_to be_success
        expect(result.exitstatus).to be_nil
        expect(result.termsig).to eq(6)
        expect(result.termination_status).to eq('Signal: SIGABRT (6)')
      end

      it 'raises command errors with signal details when signaled commands must succeed' do
        stdin = instance_double(IO, close: nil)
        stdout = stream_class.new([EOFError.new])
        stderr = stream_class.new(['aborted', EOFError.new])
        wait_thr = instance_double(Thread)
        status = instance_double(Process::Status, exitstatus: nil, termsig: 6)

        allow(wait_thr).to receive_messages(join: wait_thr, value: status)
        allow(Open3).to receive(:popen3).and_yield(stdin, stdout, stderr, wait_thr)

        captured_error = begin
          executor.run_command_using_args(%w[nmcli radio wifi])
        rescue WifiWand::CommandExecutor::OsCommandError => e
          e
        end

        expect(captured_error).to be_a(WifiWand::CommandExecutor::OsCommandError)
        expect(captured_error.message).to match(/aborted/)
        expect(captured_error.display_message).to include('Signal: SIGABRT (6)')
      end

      it 'wraps temporary process spawn failures with command context' do
        allow(Open3).to receive(:popen3)
          .and_raise(Errno::EAGAIN, 'Resource temporarily unavailable')

        expect do
          executor.run_command_using_args(%w[nmcli radio wifi])
        end.to raise_error(WifiWand::CommandSpawnError, /nmcli radio wifi.*Resource temporarily unavailable/)
      end
    end

    context 'with shell string commands' do
      let(:executor) { described_class.new(verbose: false) }

      it 'captures both stdout and stderr' do
        result = executor.run_command_using_shell("bash -c 'echo \"stdout\"; echo \"stderr\" >&2'",
          raise_on_error: false)
        expect(result.stdout).to include('stdout')
        expect(result.stderr).to include('stderr')
      end

      it 'raises CommandTimeoutError for shell commands that exceed the timeout' do
        expect do
          executor.run_command_using_shell("#{RbConfig.ruby} -e 'sleep 5'", raise_on_error: true,
            timeout_in_secs: 0.2)
        end.to raise_error(WifiWand::CommandTimeoutError, /sleep 5/)
      end
    end

    context 'with verbose mode enabled' do
      let(:executor) { described_class.new(verbose: true) }

      it 'outputs command attempt and duration info' do
        expect do
          executor.run_command_using_shell('echo "test"')
        end.to output(/Command:.*echo "test".*Duration:.*seconds/m).to_stdout
      end

      it 'warns when forceful reader cleanup does not finish promptly' do
        output = StringIO.new
        verbose_executor = described_class.new(verbose: true, output: output)
        thread = instance_double(Thread, alive?: true)

        allow(thread).to receive(:join).with(described_class::READER_THREAD_JOIN_WAIT_SECS).and_return(nil)
        allow(thread).to receive(:kill)

        verbose_executor.send(:cleanup_reader_threads, [thread])

        expect(output.string).to include(
          'Warning: forcing command output reader thread termination after timeout'
        )
        expect(output.string).to include(
          'Warning: command output reader thread did not terminate after forceful cleanup'
        )
      end

      it 'warns when cleanup recovers an inherited-pipe reader' do
        Tempfile.create('wifiwand-command-inherited-pipes-verbose') do |pid_file|
          output = StringIO.new
          verbose_executor = described_class.new(verbose: true, output: output)
          pid_file.close

          result = run_command_in_thread(verbose_executor, inherited_pipe_command(pid_file))

          expect(result.stdout).to include('parent done')
          expect(output.string).to include(
            'Warning: command output reader thread did not finish before cleanup'
          )
        ensure
          terminate_pid_from_file(pid_file)
        end
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

      allow(executor).to receive(:run_command_using_args) do |command|
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

    it 'returns false when PATH is unset' do
      original_path = ENV['PATH']
      ENV.delete('PATH')

      expect(executor.command_available?('echo')).to be false
    ensure
      original_path ? (ENV['PATH'] = original_path) : ENV.delete('PATH')
    end

    it 'checks executable files in PATH directories' do
      allow(ENV).to receive(:fetch).with('PATH', '').and_return('/usr/bin:/bin')
      allow(File).to receive_messages(executable?: false, directory?: false)
      allow(File).to receive(:executable?).with('/usr/bin/test_cmd').and_return(true)

      expect(executor.command_available?('test_cmd')).to be true
    end

    it 'excludes directories even if marked executable' do
      allow(ENV).to receive(:fetch).with('PATH', '').and_return('/usr/bin')
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

    it 'uses command output as the exception message' do
      expect(error.message).to eq('command failed')
      expect(error.to_s).to eq('command failed')
    end

    it 'provides a user-facing display message with command context' do
      expect(error.display_message).to eq(<<~MESSAGE.chomp)
        command failed
        Command failed: false
        Exit code: 1
      MESSAGE
    end

    it 'omits the command output line from display message when output is empty' do
      error = described_class.new(exitstatus: 7, command: 'silent-command', text: '')

      expect(error.display_message).to eq(<<~MESSAGE.chomp)
        Command failed: silent-command
        Exit code: 7
      MESSAGE
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

      expect do
        WifiWand::BaseModel.new(verbose: false)
      end.not_to raise_error
    end
  end
end
