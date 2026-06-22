# frozen_string_literal: true

require 'rbconfig'
require 'tempfile'
require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/services/command_executor'

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

  # Signal 6 is SIGABRT on CRuby and SIGIOT on JRuby; both names are valid.
  let(:signal_6_status_regex) { /Signal: SIG(?:ABRT|IOT) \(6\)/ }

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

          def binmode
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

      it 'captures binary stdout bytes without UTF-8 transcoding' do
        expected_bytes = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]

        result = executor.run_command_using_args(
          [
            RbConfig.ruby,
            '-e',
            "STDOUT.binmode; STDOUT.write #{expected_bytes.inspect}.pack('C*')",
          ],
          binary_stdout: true
        )

        expect(result.stdout.encoding).to eq(Encoding::BINARY)
        expect(result.stdout.bytes).to eq(expected_bytes)
        expect(result.combined_output.encoding).to eq(Encoding::BINARY)
        expect(result.combined_output.bytes).to eq(expected_bytes)
      end

      it 'keeps stderr text encoding when stdout is binary' do
        stdin = instance_double(IO, close: nil)
        stdout_chunk = "\x89P".b
        stderr_chunk = 'warning: déjà vu'.encode(Encoding::UTF_8)
        stdout = stream_class.new([stdout_chunk, EOFError.new])
        stderr = stream_class.new([stderr_chunk, EOFError.new])
        wait_thr = instance_double(Thread)
        status = instance_double(Process::Status, exitstatus: 0, termsig: nil)

        expect(stdout_chunk).to receive(:b).at_least(:once).and_call_original
        allow(wait_thr).to receive_messages(join: wait_thr, value: status)
        allow(Open3).to receive(:popen3).and_yield(stdin, stdout, stderr, wait_thr)

        result = executor.run_command_using_args(%w[qrencode -t PNG -o - payload], binary_stdout: true)

        expect(result.stdout.encoding).to eq(Encoding::BINARY)
        expect(result.stdout.bytes).to eq([0x89, 0x50])
        expect(result.stderr.encoding).to eq(Encoding::UTF_8)
        expect(result.stderr).to eq('warning: déjà vu')
        expect(stderr_chunk.encoding).to eq(Encoding::UTF_8)
        expect(result.combined_output.encoding).to eq(Encoding::BINARY)
        valid_combined_byte_orders = [
          stdout_chunk.bytes + stderr_chunk.bytes,
          stderr_chunk.bytes + stdout_chunk.bytes,
        ]
        expect(valid_combined_byte_orders).to include(result.combined_output.bytes)
      end

      it 'treats stdout and stderr EOF as normal command shutdown' do
        stdin = instance_double(IO, close: nil)
        stdout = stream_class.new(['partial output', EOFError.new])
        stderr = stream_class.new(['warning output', EOFError.new])
        wait_thr = instance_double(Thread)
        status = instance_double(Process::Status, exitstatus: 0, termsig: nil)
        result = nil

        allow(wait_thr).to receive_messages(join: wait_thr, value: status)
        allow(Open3).to receive(:popen3).and_yield(stdin, stdout, stderr, wait_thr)

        expect do
          result = executor.run_command_using_args(%w[echo test])
        end.not_to output.to_stderr_from_any_process

        expect(result.stdout).to eq('partial output')
        expect(result.stderr).to eq('warning output')
        expect(result.combined_output).to include('partial output')
        expect(result.combined_output).to include('warning output')
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
        stub_const("#{described_class}::COMMAND_KILL_WAIT_SECS", 0.05)

        Tempfile.create('wifiwand-command-timeout') do |pid_file|
          pid_file.close
          command = [
            'sh',
            '-c',
            "printf '%s' $$ > \"$1\"; trap '' TERM; sleep 30",
            'sh',
            pid_file.path,
          ]

          expect { executor.run_command_using_args(command, raise_on_error: true, timeout_in_secs: 0.1) }
            .to raise_error(WifiWand::CommandTimeoutError)

          pid = wait_for_file_contents(pid_file.path).to_i
          wait_for_process_exit(pid)
          expect(process_alive?(pid)).to be(false)
        end
      end

      it 'terminates descendant processes created by a timed out command' do
        stub_const("#{described_class}::COMMAND_KILL_WAIT_SECS", 0.05)

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

          expect { executor.run_command_using_args(command, raise_on_error: true, timeout_in_secs: 0.1) }
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

      it 'ignores IOError while closing command streams' do
        stream = instance_double(IO, closed?: false)

        allow(stream).to receive(:close).and_raise(IOError, 'already closed')

        expect { executor.send(:close_command_streams, stream) }.not_to raise_error
      end

      it 'reports a process group as not alive when signal probing raises ESRCH' do
        allow(Process).to receive(:kill).with(0, -12_345).and_raise(Errno::ESRCH)

        expect(executor.send(:process_group_alive?, 12_345)).to be(false)
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
        expect(result.termination_status).to match(signal_6_status_regex)
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
        expect(captured_error.message).to include('aborted')
        expect(captured_error.display_message).to match(signal_6_status_regex)
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
        end.to output(/Command:.*echo "test".*Duration:.*seconds/m).to_stderr
      end

      it 'can suppress verbose stdout logging while still returning stdout' do
        err_output = StringIO.new
        verbose_executor = described_class.new(
          runtime_config: WifiWand::RuntimeConfig.new(verbose: true, err_stream: err_output)
        )

        result = verbose_executor.run_command_using_args(
          [RbConfig.ruby, '-e', 'STDOUT.write 115.chr + 101.chr + 99.chr + 114.chr + 101.chr + 116.chr'],
          log_stdout: false
        )

        expect(result.stdout).to eq('secret')
        expect(err_output.string).to include('Command:')
        expect(err_output.string).to include('Duration:')
        expect(err_output.string).not_to include('STDOUT:')
        expect(err_output.string).not_to include('secret')
      end

      it 'outputs UTC timestamps when runtime config requests UTC' do
        err_output = StringIO.new
        verbose_executor = described_class.new(
          runtime_config: WifiWand::RuntimeConfig.new(verbose: true, utc: true, err_stream: err_output)
        )

        verbose_executor.run_command_using_shell('echo "test"')

        expect(err_output.string).to match(/Duration: .* seconds -- \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
      end

      it 'outputs local timestamps by default' do
        err_output = StringIO.new
        verbose_executor = described_class.new(
          runtime_config: WifiWand::RuntimeConfig.new(verbose: true, err_stream: err_output)
        )
        fixed_time = Time.new(2026, 5, 17, 18, 3, 50, '+07:00')

        allow(Time).to receive(:now).and_return(fixed_time)

        verbose_executor.run_command_using_shell('echo "test"')

        expect(err_output.string).to include("seconds -- #{fixed_time.getlocal.iso8601}")
      end

      it 'warns when forceful reader cleanup does not finish promptly' do
        err_output = StringIO.new
        verbose_executor = described_class.new(
          runtime_config: WifiWand::RuntimeConfig.new(verbose: true, err_stream: err_output)
        )
        thread = instance_double(Thread, alive?: true)

        allow(thread).to receive(:join).with(described_class::READER_THREAD_JOIN_WAIT_SECS).and_return(nil)
        allow(thread).to receive(:kill)

        verbose_executor.send(:cleanup_reader_threads, [thread])

        expect(err_output.string).to include(
          'Warning: forcing command output reader thread termination after timeout'
        )
        expect(err_output.string).to include(
          'Warning: command output reader thread did not terminate after forceful cleanup'
        )
      end

      it 'warns when cleanup recovers an inherited-pipe reader' do
        Tempfile.create('wifiwand-command-inherited-pipes-verbose') do |pid_file|
          err_output = StringIO.new
          verbose_executor = described_class.new(
            runtime_config: WifiWand::RuntimeConfig.new(verbose: true, err_stream: err_output)
          )
          pid_file.close

          result = run_command_in_thread(verbose_executor, inherited_pipe_command(pid_file))

          expect(result.stdout).to include('parent done')
          expect(err_output.string).to include(
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

    it 'sleeps between failed attempts' do
      allow(executor).to receive(:run_command_using_args).and_return(
        WifiWand::CommandExecutor::OsCommandResult.new(
          stdout:          'not yet',
          stderr:          '',
          combined_output: 'not yet',
          exitstatus:      0,
          command:         %w[echo test],
          duration:        0.0
        )
      )

      expect(executor).to receive(:sleep)
        .with(described_class::TRY_OS_COMMAND_RETRY_SLEEP_SECS)
        .twice

      executor.try_os_command_until(%w[echo test], ->(_output) { false }, 3)
    end

    it 'does not sleep after the final failed attempt' do
      allow(executor).to receive(:run_command_using_args).and_return(
        WifiWand::CommandExecutor::OsCommandResult.new(
          stdout:          'not yet',
          stderr:          '',
          combined_output: 'not yet',
          exitstatus:      0,
          command:         %w[echo test],
          duration:        0.0
        )
      )

      expect(executor).not_to receive(:sleep)

      executor.try_os_command_until(%w[echo test], ->(_output) { false }, 1)
    end

    it 'returns nil when max_tries is reached without success' do
      condition = ->(_output) { false }
      expect(executor.try_os_command_until(%w[echo fail], condition, 2)).to be_nil
    end

    it 'reports attempt count in verbose mode' do
      err_output = StringIO.new
      verbose_executor = described_class.new(
        runtime_config: WifiWand::RuntimeConfig.new(verbose: true, err_stream: err_output)
      )
      condition = ->(_output) { true }
      verbose_executor.try_os_command_until(%w[echo test], condition, 3)
      expect(err_output.string).to include('Command was executed 1 time')
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
      require_relative '../../../lib/wifi_wand/models/base_model'

      expect do
        WifiWand::BaseModel.new(verbose: false)
      end.not_to raise_error
    end
  end
end
