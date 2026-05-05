# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'stringio'

RSpec.describe WifiWand::MacOsHelperBundle do
  describe WifiWand::MacOsHelperClient do
    subject(:client) do
      described_class.new(
        out_stream_proc:    -> { out_stream },
        verbose_proc:       -> { verbose_flag },
        macos_version_proc: -> { macos_version }
      )
    end

    let(:out_stream) { StringIO.new }
    let(:verbose_flag) { false }
    let(:macos_version) { '14.0' }

    around do |example|
      original = ENV['WIFIWAND_DISABLE_MAC_HELPER']
      ENV.delete('WIFIWAND_DISABLE_MAC_HELPER')
      example.run
    ensure
      ENV['WIFIWAND_DISABLE_MAC_HELPER'] = original
    end

    describe '#available?' do
      context 'when the helper is already disabled' do
        before { client.instance_variable_set(:@disabled, true) }

        it 'returns false' do
          expect(client.available?).to be(false)
        end
      end

      context 'when the disable env flag is set' do
        before { ENV['WIFIWAND_DISABLE_MAC_HELPER'] = '1' }

        it 'returns false' do
          expect(client.available?).to be(false)
        end
      end

      context 'when the macOS version is missing' do
        let(:macos_version) { nil }

        it 'returns false' do
          expect(client.available?).to be(false)
        end
      end

      context 'when the version string cannot be sanitized' do
        let(:macos_version) { 'developer seed' }

        it 'returns false' do
          expect(client.available?).to be(false)
        end
      end

      context 'when the version is older than the minimum helper version' do
        let(:macos_version) { '13.6.1' }

        it 'returns false' do
          expect(client.available?).to be(false)
        end
      end

      context 'when the version meets the minimum helper version' do
        let(:macos_version) { '15.0 (24A335)' }

        it 'returns true' do
          expect(client.available?).to be(true)
        end

        it 'uses the centralized helper support predicate' do
          expect(WifiWand::MacOsHelperBundle)
            .to receive(:helper_support_status_for_macos_version).with('15.0 (24A335)').and_call_original

          client.available?
        end
      end
    end

    describe '#connected_network_name' do
      subject(:client) do
        Class.new(described_class) do
          def initialize(execute_result:, **kwargs)
            super(**kwargs)
            @execute_result = execute_result
          end

          private def execute(_command, **_kwargs) = @execute_result
        end.new(
          execute_result:     raw_result,
          out_stream_proc:    -> { out_stream },
          verbose_proc:       -> { verbose_flag },
          macos_version_proc: -> { macos_version }
        )
      end

      let(:raw_result) { WifiWand::MacOsHelperBundle::HelperQueryResult.new }

      it 'parses the new connected response with an SSID payload' do
        raw_result.payload = { 'status' => 'connected', 'ssid' => 'OfficeWiFi' }
        raw_result.status = :success
        result = client.connected_network_name
        expect(result).to be_a(WifiWand::MacOsHelperBundle::HelperQueryResult)
        expect(result.payload).to eq('OfficeWiFi')
        expect(result.status).to eq(:connected)
        expect(result).to be_connected
        expect(result).not_to be_location_services_blocked
      end

      it 'remains compatible with old helper responses that only include an SSID' do
        raw_result.payload = { 'ssid' => 'OfficeWiFi' }
        raw_result.status = :success
        result = client.connected_network_name
        expect(result.payload).to eq('OfficeWiFi')
        expect(result.status).to eq(:connected)
        expect(result).to be_connected
      end

      it 'returns a result with nil payload when the helper does not respond' do
        result = client.connected_network_name
        expect(result.payload).to be_nil
        expect(result.status).to eq(:unknown)
        expect(result).to be_ambiguous
        expect(result).not_to be_not_connected
        expect(result).not_to be_location_services_blocked
      end

      it 'parses the new not-connected response without relying on nil SSID inference' do
        raw_result.payload = { 'status' => 'not_connected', 'interface' => 'en0' }
        raw_result.status = :success
        result = client.connected_network_name
        expect(result.payload).to be_nil
        expect(result.status).to eq(:not_connected)
        expect(result).to be_not_connected
        expect(result).not_to be_location_services_blocked
      end

      it 'keeps old helper nil SSID responses ambiguous instead of treating them as disconnected' do
        raw_result.payload = { 'status' => 'ok', 'ssid' => nil }
        raw_result.status = :success
        result = client.connected_network_name
        expect(result.payload).to be_nil
        expect(result.status).to eq(:unknown)
        expect(result).to be_ambiguous
        expect(result).not_to be_not_connected
      end

      it 'keeps old helper omitted SSID responses ambiguous instead of treating them as disconnected' do
        raw_result.payload = { 'status' => 'ok', 'interface' => 'en0' }
        raw_result.status = :success
        result = client.connected_network_name
        expect(result.payload).to be_nil
        expect(result.status).to eq(:unknown)
        expect(result).to be_ambiguous
        expect(result).not_to be_not_connected
      end

      it 'classifies Location Services errors distinctly' do
        raw_result.location_services_blocked = true
        raw_result.error_message = 'Location Services denied'
        raw_result.status = :location_services_blocked
        result = client.connected_network_name
        expect(result.payload).to be_nil
        expect(result.status).to eq(:location_services_blocked)
        expect(result).to be_location_services_blocked
      end

      it 'classifies explicit helper permission errors distinctly from not-connected' do
        raw_result.status = :permission_denied
        raw_result.location_services_blocked = true
        raw_result.error_message = 'Location Services denied'
        result = client.connected_network_name
        expect(result.payload).to be_nil
        expect(result.status).to eq(:permission_denied)
        expect(result).to be_permission_denied
        expect(result).to be_location_services_blocked
        expect(result).not_to be_not_connected
      end

      it 'keeps helper unavailability ambiguous instead of treating it as disconnected' do
        raw_result.status = :unavailable
        result = client.connected_network_name
        expect(result.payload).to be_nil
        expect(result.status).to eq(:unavailable)
        expect(result).to be_ambiguous
        expect(result).not_to be_not_connected
      end

      it 'keeps malformed helper payloads non-fatal and ambiguous' do
        raw_result.payload = { 'status' => 'ok' }
        raw_result.status = :success
        result = client.connected_network_name
        expect(result.payload).to be_nil
        expect(result.status).to eq(:unknown)
        expect(result).to be_ambiguous
      end

      it 'classifies a non-object helper payload as an error' do
        raw_result.payload = []
        raw_result.status = :success
        result = client.connected_network_name
        expect(result.payload).to be_nil
        expect(result.status).to eq(:error)
        expect(result).to be_ambiguous
      end

      it 'preserves placeholder SSID payloads without classifying them as real connections' do
        raw_result.payload = { 'status' => 'ok', 'ssid' => '<redacted>' }
        raw_result.status = :success
        result = client.connected_network_name
        expect(result.payload).to eq('<redacted>')
        expect(result.status).to eq(:unknown)
        expect(result).to be_ambiguous
      end
    end

    describe '#scan_networks' do
      subject(:client) do
        Class.new(described_class) do
          def initialize(execute_result:, **kwargs)
            super(**kwargs)
            @execute_result = execute_result
          end

          private def execute(_command, **_kwargs) = @execute_result
        end.new(
          execute_result:     raw_result,
          out_stream_proc:    -> { out_stream },
          verbose_proc:       -> { verbose_flag },
          macos_version_proc: -> { macos_version }
        )
      end

      let(:raw_result) { WifiWand::MacOsHelperBundle::HelperQueryResult.new }

      it 'returns a result with network data payload' do
        raw_result.payload = { 'networks' => [{ 'ssid' => 'Cafe' }] }
        raw_result.status = :success
        result = client.scan_networks
        expect(result).to be_a(WifiWand::MacOsHelperBundle::HelperQueryResult)
        expect(result.payload).to eq([{ 'ssid' => 'Cafe' }])
        expect(result.status).to eq(:success)
        expect(result).not_to be_ambiguous
        expect(result).not_to be_location_services_blocked
      end

      it 'returns a result with empty array payload when the helper does not respond' do
        result = client.scan_networks
        expect(result.payload).to eq([])
        expect(result.status).to eq(:unknown)
        expect(result).not_to be_location_services_blocked
      end

      {
        unavailable:               { ambiguous: true },
        timeout:                   { ambiguous: true },
        error:                     { ambiguous: true, error_message: 'helper failed' },
        permission_denied:         {
          ambiguous:                 false,
          error_message:             'Location Services denied',
          location_services_blocked: true,
        },
        location_services_blocked: {
          ambiguous:                 false,
          error_message:             'Location Services denied',
          location_services_blocked: true,
        },
      }.each do |status, result_attributes|
        it "passes through #{status} scan result status" do
          raw_result.status = status
          raw_result.error_message = result_attributes[:error_message]
          raw_result.location_services_blocked = result_attributes[:location_services_blocked]

          result = client.scan_networks
          expect(result.payload).to eq([])
          expect(result.status).to eq(status)
          expect(result.ambiguous?).to eq(result_attributes[:ambiguous])
          expect(result.location_services_blocked?).to eq(!!result_attributes[:location_services_blocked])
        end
      end
    end

    describe '#location_services_blocked?' do
      it 'returns true when the last helper error was a denied Location Services permission' do
        client.send(:handle_error, 'Location Services denied')
        expect(client.location_services_blocked?).to be(true)
      end

      it 'returns true when an explicit permission status has a nonstandard message' do
        client.send(:handle_error, 'permission rejected by macOS', helper_status: 'permission_denied')
        expect(client.location_services_blocked?).to be(true)
      end

      it 'returns true when an explicit blocked status has a nonstandard message' do
        client.send(:handle_error, 'system location toggle is off',
          helper_status: 'location_services_blocked')
        expect(client.location_services_blocked?).to be(true)
      end

      it 'returns false when the last Location Services error was an authorization timeout' do
        client.send(:handle_error, 'Location Services authorization timed out')
        expect(client.location_services_blocked?).to be(false)
      end

      it 'returns false when the last Location Services error was an unknown authorization state' do
        client.send(:handle_error, 'Location Services authorization status is unknown')
        expect(client.location_services_blocked?).to be(false)
      end

      it 'returns false when the last helper error was unrelated' do
        client.send(:handle_error, 'unexpected failure')
        expect(client.location_services_blocked?).to be(false)
      end
    end

    describe WifiWand::MacOsHelperBundle::HelperQueryResult do
      describe '#location_services_error?' do
        it 'returns true for denied Location Services permission blocks' do
          result = described_class.new(
            location_services_blocked: true,
            error_message:             'Location Services denied',
            status:                    :location_services_blocked
          )

          expect(result).to be_location_services_error
        end

        it 'normalizes permission-denied status into the blocked predicate' do
          result = described_class.new(status: :permission_denied)

          expect(result).to be_location_services_blocked
          expect(result).to be_location_services_error
        end

        it 'returns true for Location Services authorization timeouts' do
          result = described_class.new(
            error_message: 'Location Services authorization timed out',
            status:        :timeout
          )

          expect(result).to be_location_services_error
        end

        it 'returns true for unknown Location Services authorization states' do
          result = described_class.new(
            error_message: 'Location Services authorization status is unknown',
            status:        :unknown
          )

          expect(result).to be_location_services_error
        end

        it 'returns true for unclassified Location Services helper errors' do
          result = described_class.new(
            error_message: 'Location Services authorization cancelled',
            status:        :error
          )

          expect(result).to be_location_services_error
          expect(result).not_to be_location_services_blocked
        end

        it 'returns false for generic helper timeouts without Location Services context' do
          result = described_class.new(status: :timeout)

          expect(result).not_to be_location_services_error
        end

        it 'returns false for bare authorization timeouts without Location Services context' do
          result = described_class.new(error_message: 'authorization timed out', status: :timeout)

          expect(result).not_to be_location_services_error
        end

        it 'returns false for generic helper errors' do
          result = described_class.new(error_message: 'unexpected failure', status: :error)

          expect(result).not_to be_location_services_error
        end
      end
    end

    describe '#execute' do
      subject(:execute_command) { client.send(:execute, command) }

      let(:client) do
        client_class.new(
          available_result:     helper_available,
          executable_available: executable_available,
          helper_command_proc:  helper_command_proc,
          parse_json_result:    parse_json_result,
          out_stream_proc:      -> { out_stream },
          verbose_proc:         -> { verbose_flag },
          macos_version_proc:   -> { macos_version }
        )
      end

      let(:client_class) do
        Class.new(described_class) do
          attr_reader :handled_errors, :log_messages, :helper_command_invocations, :available_timeouts,
            :install_timeouts, :helper_command_timeouts

          def initialize(
            available_result:, executable_available:, helper_command_proc:, parse_json_result:, **kwargs
          )
            super(**kwargs)
            @available_result = available_result
            @executable_available = executable_available
            @helper_command_proc = helper_command_proc
            @parse_json_result = parse_json_result
            @handled_errors = []
            @log_messages = []
            @helper_command_invocations = 0
            @available_timeouts = []
            @install_timeouts = []
            @helper_command_timeouts = []
          end

          private def helper_availability_status(timeout_seconds: nil)
            @available_timeouts << timeout_seconds
            return @available_result unless [true, false].include?(@available_result)

            @available_result ? :available : :unavailable
          end

          private def ensure_helper_installed(timeout_seconds: nil)
            @install_timeouts << timeout_seconds
          end

          private def helper_executable_available?
            @executable_available
          end

          private def execute_helper_command(command, timeout_seconds: nil)
            @helper_command_invocations += 1
            @helper_command_timeouts << timeout_seconds
            @helper_command_proc.call(command)
          end

          private def parse_json(_text)
            return super if @parse_json_result == :__use_super__

            @parse_json_result
          end

          private def handle_error(message, **kwargs)
            @handled_errors << message
            super
          end

          private def log_verbose(message)
            @log_messages << message
          end
        end
      end

      let(:command) { 'scan-networks' }
      let(:helper_available) { true }
      let(:executable_available) { true }
      let(:parse_json_result) { :__use_super__ }
      let(:helper_command_proc) { ->(_command) { raise 'override in example' } }

      context 'when the helper is unavailable' do
        let(:helper_available) { false }
        let(:helper_command_proc) { ->(_command) { raise 'should not run' } }

        it 'returns an empty result without invoking the executable' do
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsHelperBundle::HelperQueryResult)
          expect(result.payload).to be_nil
          expect(result.status).to eq(:unavailable)
          expect(result).to be_ambiguous
          expect(result).not_to be_not_connected
          expect(result).not_to be_location_services_blocked
          expect(client.helper_command_invocations).to eq(0)
        end
      end

      context 'when helper availability is unknown' do
        let(:helper_available) { :unknown }
        let(:helper_command_proc) { ->(_command) { raise 'should not run' } }

        it 'returns an ambiguous result without treating the machine as disconnected' do
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsHelperBundle::HelperQueryResult)
          expect(result.payload).to be_nil
          expect(result.status).to eq(:unknown)
          expect(result).to be_ambiguous
          expect(result).not_to be_not_connected
          expect(client.helper_command_invocations).to eq(0)
        end
      end

      context 'when the helper command succeeds' do
        let(:status) { instance_double(Process::Status, success?: true) }
        let(:helper_command_proc) do
          ->(_command) do
            {
              stdout: '{"status":"ok","payload":1}',
              stderr: '',
              status: status,
            }
          end
        end

        it 'returns a result with the parsed payload' do
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsHelperBundle::HelperQueryResult)
          expect(result.payload).to eq('status' => 'ok', 'payload' => 1)
          expect(result.status).to eq(:success)
          expect(result).not_to be_ambiguous
          expect(result).not_to be_location_services_blocked
        end

        it 'propagates the remaining bounded lookup budget through preflight and command execution' do
          client.send(:execute, command, timeout_seconds: 0.5)

          expect(client.available_timeouts.first).to be_between(0, 0.5).exclusive
          expect(client.install_timeouts.first).to be_between(0, 0.5).exclusive
          expect(client.helper_command_timeouts.first).to be_between(0, 0.5).exclusive
        end
      end

      context 'when the helper exits with a non-zero status' do
        let(:status) { instance_double(Process::Status, success?: false, exitstatus: 64) }
        let(:helper_command_proc) do
          ->(_command) do
            {
              stdout: '',
              stderr: 'boom',
              status: status,
            }
          end
        end

        it 'logs the failure and returns an empty result' do
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsHelperBundle::HelperQueryResult)
          expect(result.payload).to be_nil
          expect(result.status).to eq(:error)
          expect(client.log_messages).to include('helper exited with status 64: boom')
        end
      end

      context 'when the helper exits non-zero with a JSON error payload' do
        let(:status) { instance_double(Process::Status, success?: false, exitstatus: 1) }
        let(:helper_error_message) { 'Location Services denied' }
        let(:helper_stderr) { 'helper diagnostic' }
        let(:helper_command_proc) do
          ->(_command) do
            {
              stdout: %({"status":"error","error":"#{helper_error_message}"}),
              stderr: helper_stderr,
              status: status,
            }
          end
        end

        it 'classifies the helper error before falling back to the exit status' do
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsHelperBundle::HelperQueryResult)
          expect(result.payload).to be_nil
          expect(result.status).to eq(:location_services_blocked)
          expect(result).to be_location_services_blocked
          expect(result.error_message).to eq('Location Services denied')
          expect(client.handled_errors).to include('Location Services denied')
          expect(client.log_messages).to include('helper exited with status 1: helper diagnostic')
        end

        context 'with a Location Services authorization timeout' do
          let(:helper_error_message) { 'Location Services authorization timed out' }

          it 'classifies the result as a timeout instead of a permission block' do
            result = execute_command
            expect(result.payload).to be_nil
            expect(result.status).to eq(:timeout)
            expect(result).to be_ambiguous
            expect(result).not_to be_location_services_blocked
            expect(result.error_message).to eq('Location Services authorization timed out')
          end
        end

        context 'with an unknown Location Services authorization status' do
          let(:helper_error_message) { 'Location Services authorization status is unknown' }

          it 'classifies the result as unknown instead of a permission block' do
            result = execute_command
            expect(result.payload).to be_nil
            expect(result.status).to eq(:unknown)
            expect(result).to be_ambiguous
            expect(result).not_to be_location_services_blocked
            expect(result.error_message).to eq('Location Services authorization status is unknown')
          end
        end

        context 'with a bare authorization timeout' do
          let(:helper_error_message) { 'authorization timed out' }

          it 'keeps the result generic without Location Services context' do
            result = execute_command
            expect(result.payload).to be_nil
            expect(result.status).to eq(:error)
            expect(result).to be_ambiguous
            expect(result).not_to be_location_services_blocked
            expect(result).not_to be_location_services_error
            expect(result.error_message).to eq('authorization timed out')
          end
        end

        context 'with an explicit permission-denied helper status' do
          let(:helper_command_proc) do
            ->(_command) do
              {
                stdout: '{"status":"permission_denied","error":"Location Services denied"}',
                stderr: helper_stderr,
                status: status,
              }
            end
          end

          it 'preserves the permission status instead of treating it as disconnected' do
            result = execute_command
            expect(result.payload).to be_nil
            expect(result.status).to eq(:permission_denied)
            expect(result).to be_permission_denied
            expect(result).to be_location_services_blocked
            expect(result).not_to be_not_connected
            expect(result.error_message).to eq('Location Services denied')
          end
        end

        context 'with an explicit Location Services blocked helper status' do
          let(:helper_command_proc) do
            ->(_command) do
              {
                stdout: '{"status":"location_services_blocked","error":"Location Services disabled"}',
                stderr: helper_stderr,
                status: status,
              }
            end
          end

          it 'preserves the blocked status instead of falling back to message matching' do
            result = execute_command
            expect(result.payload).to be_nil
            expect(result.status).to eq(:location_services_blocked)
            expect(result).to be_location_services_blocked
            expect(result).not_to be_not_connected
            expect(result.error_message).to eq('Location Services disabled')
          end
        end
      end

      context 'when the helper output cannot be parsed' do
        let(:status) { instance_double(Process::Status, success?: true) }
        let(:helper_command_proc) { ->(_command) { { stdout: '{}', stderr: '', status: status } } }
        let(:parse_json_result) { nil }

        it 'returns an empty result' do
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsHelperBundle::HelperQueryResult)
          expect(result.payload).to be_nil
          expect(result.status).to eq(:error)
        end
      end

      context 'when the helper reports an error status' do
        let(:status) { instance_double(Process::Status, success?: true) }
        let(:helper_command_proc) do
          ->(_command) do
            {
              stdout: '{"status":"error","error":"Location Services denied"}',
              stderr: '',
              status: status,
            }
          end
        end

        it 'delegates to handle_error and returns a result with location_services_blocked' do
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsHelperBundle::HelperQueryResult)
          expect(result).to be_location_services_blocked
          expect(result.status).to eq(:location_services_blocked)
          expect(result.error_message).to eq('Location Services denied')
          expect(client.handled_errors).to include('Location Services denied')
        end
      end

      context 'when the helper times out' do
        let(:helper_command_proc) { ->(*) {} }

        it 'returns a safe empty result so callers can fall back' do
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsHelperBundle::HelperQueryResult)
          expect(result.payload).to be_nil
          expect(result.status).to eq(:timeout)
          expect(result).not_to be_location_services_blocked
          expect(result.error_message).to be_nil
        end
      end

      context 'when the bounded install check leaves the helper executable missing' do
        let(:executable_available) { false }
        let(:helper_command_proc) { ->(_command) { raise 'should not run' } }

        it 'returns unavailable instead of reporting a timeout' do
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsHelperBundle::HelperQueryResult)
          expect(result.payload).to be_nil
          expect(result.status).to eq(:unavailable)
          expect(result).to be_ambiguous
          expect(result.error_message).to be_nil
          expect(client.helper_command_invocations).to eq(0)
        end
      end

      context 'when the executable is missing' do
        let(:helper_command_proc) { ->(_command) { raise Errno::ENOENT, 'wifiwand-helper' } }

        it 'logs the error and returns an empty result' do
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsHelperBundle::HelperQueryResult)
          expect(result.payload).to be_nil
          expect(result.status).to eq(:unavailable)
          has_missing_message = client.log_messages.any? do |message|
            message.match?(/helper executable missing:/)
          end
          expect(has_missing_message).to be(true)
        end
      end

      context 'when an unexpected error occurs' do
        let(:helper_command_proc) { ->(_command) { raise StandardError, 'boom' } }

        it 'logs the failure and returns an empty result' do
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsHelperBundle::HelperQueryResult)
          expect(result.payload).to be_nil
          expect(result.status).to eq(:error)
          expect(client.log_messages).to include("helper command 'scan-networks' failed: boom")
        end
      end
    end

    describe '#execute_helper_command' do
      subject(:helper_command_result) { client.send(:execute_helper_command, command) }

      let(:command) { 'scan-networks' }
      let(:stdin) { instance_double(IO, close: nil) }
      let(:stdout) { StringIO.new('{"status":"ok"}') }
      let(:stderr) { StringIO.new('') }
      let(:status) { instance_double(Process::Status, success?: true) }
      let(:wait_join_result) { :finished }
      let(:wait_thr) { double('wait thread', join: wait_join_result, value: status, pid: 4321) }

      before do
        allow(WifiWand::MacOsHelperBundle).to receive(:installed_executable_path).and_return('/tmp/helper')
        allow(WifiWand::MacOsHelperBundle).to receive(:helper_command_timeout_seconds)
          .with(command).and_return(4.5)
        allow(Open3).to receive(:popen3).with('/tmp/helper', command)
          .and_yield(stdin, stdout, stderr, wait_thr)
      end

      it 'returns stdout, stderr, and status for successful runs' do
        result = helper_command_result
        expect(result).to eq(stdout: '{"status":"ok"}', stderr: '', status: status)
      end

      it 'passes the command-specific timeout to the helper runner' do
        allow(WifiWand::MacOsHelperBundle).to receive(:run_bounded_helper_command).and_return(
          stdout: '{"status":"ok"}', stderr: '', status: status
        )

        helper_command_result

        expect(WifiWand::MacOsHelperBundle).to have_received(:run_bounded_helper_command).with(
          '/tmp/helper',
          command,
          timeout_seconds: 4.5,
          on_timeout:      kind_of(Proc)
        )
      end

      context 'when the helper never exits before the deadline' do
        let(:stdout) { instance_double(IO, read: '', close: nil, closed?: false) }
        let(:stderr) { instance_double(IO, read: '', close: nil, closed?: false) }
        let(:wait_join_result) { nil }
        let(:verbose_flag) { true }

        it 'logs the timeout and returns nil' do
          timeout_seconds = 4.5
          timeout_message =
            "helper command 'scan-networks' timed out after #{timeout_seconds}s"

          expect(helper_command_result).to be_nil
          expect(out_stream.string).to include(timeout_message)
        end
      end
    end

    describe '#ensure_helper_installed' do
      let(:helper_path) { '/tmp/helper' }

      before do
        allow(WifiWand::MacOsHelperBundle).to receive(:installed_executable_path).and_return(helper_path)
      end

      context 'when the helper executable is present and valid' do
        it 'returns immediately without reinstalling' do
          expect(File).to receive(:executable?).with(helper_path).and_return(true)
          expect(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?).and_return(true)
          expect(WifiWand::MacOsHelperBundle).not_to receive(:ensure_helper_installed)
          client.send(:ensure_helper_installed)
        end

        it 'caches successful validation for subsequent calls' do
          expect(File).to receive(:executable?).with(helper_path).and_return(true).once
          expect(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?).and_return(true).once

          2.times { client.send(:ensure_helper_installed) }
        end
      end

      context 'when the helper executable is missing' do
        let(:verbose_flag) { true }

        it 'installs the helper' do
          expect(File).to receive(:executable?).with(helper_path).and_return(false)
          expect(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?).and_return(false)
          expect(WifiWand::MacOsHelperBundle).to receive(:ensure_helper_installed)
            .with(out_stream: out_stream)
          client.send(:ensure_helper_installed)
          expect(out_stream.string).to include('helper not installed; running installer')
        end

        it 'does not install the helper during a bounded status lookup' do
          expect(File).to receive(:executable?).with(helper_path).and_return(false)
          expect(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?)
            .with(timeout_seconds: 0.1).and_return(false)
          expect(WifiWand::MacOsHelperBundle).not_to receive(:ensure_helper_installed)

          client.send(:ensure_helper_installed, timeout_seconds: 0.1)
        end

        it 'disables helper retries after an install failure' do
          expect(File).to receive(:executable?).with(helper_path).and_return(false).once
          expect(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?)
            .and_return(false).once
          expect(WifiWand::MacOsHelperBundle).to receive(:ensure_helper_installed)
            .with(out_stream: out_stream).ordered.and_raise(StandardError, 'boom')

          client.send(:ensure_helper_installed)

          expect(out_stream.string).to include('failed to install helper (boom)')
          expect(out_stream.string).not_to include('wifi-wand-macos-setup --reinstall')
          expect(client.available?).to be(false)

          client.send(:ensure_helper_installed)

          expect(client.instance_variable_get(:@helper_install_verified)).to be(false)
        end
      end

      context 'when the helper executable is present but invalid' do
        let(:verbose_flag) { true }

        it 'attempts reinstall through the module installer' do
          expect(File).to receive(:executable?).with(helper_path).and_return(true)
          expect(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?).and_return(false)
          expect(WifiWand::MacOsHelperBundle).to receive(:ensure_helper_installed)
            .with(out_stream: out_stream)
          client.send(:ensure_helper_installed)
          expect(out_stream.string)
            .to include('existing helper install failed validation; attempting reinstall')
        end

        it 'emits reinstall guidance and disables helper retries when reinstall fails' do
          expect(File).to receive(:executable?).with(helper_path).and_return(true).once
          expect(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?)
            .and_return(false).once
          expect(WifiWand::MacOsHelperBundle).to receive(:ensure_helper_installed)
            .with(out_stream: out_stream).once.and_raise(StandardError, 'boom')

          2.times { client.send(:ensure_helper_installed) }

          expect(out_stream.string).to include('failed to install helper (boom)')
          expect(out_stream.string).to include('wifi-wand-macos-setup --reinstall')
          expect(client.available?).to be(false)
        end
      end

      context 'when the helper is explicitly disabled by env' do
        before { ENV['WIFIWAND_DISABLE_MAC_HELPER'] = '1' }

        it 'does not attempt validation or installation retries' do
          expect(File).not_to receive(:executable?)
          expect(WifiWand::MacOsHelperBundle).not_to receive(:helper_installed_and_valid?)
          expect(WifiWand::MacOsHelperBundle).not_to receive(:ensure_helper_installed)

          2.times { client.send(:ensure_helper_installed) }
        end
      end

      context 'when reinstall succeeds after validation failure' do
        let(:verbose_flag) { true }

        it 'marks the helper as verified for later calls' do
          expect(File).to receive(:executable?).with(helper_path).and_return(true).once
          expect(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?)
            .and_return(false).once
          expect(WifiWand::MacOsHelperBundle).to receive(:ensure_helper_installed)
            .with(out_stream: out_stream).once

          2.times { client.send(:ensure_helper_installed) }
        end
      end
    end

    describe '#parse_json' do
      it 'returns parsed data for valid JSON' do
        expect(client.send(:parse_json, '{"foo":1}')).to eq('foo' => 1)
      end

      it 'logs an error when parsing fails' do
        allow(client.instance_variable_get(:@verbose_proc)).to receive(:call).and_return(true)
        expect(client.send(:parse_json, '{invalid-json')).to be_nil
        expect(out_stream.string).to match(/failed to parse helper JSON:/)
      end
    end

    describe '#handle_error' do
      it 'emits a location warning when permissions are denied' do
        client.send(:handle_error, 'Location Services denied by user')
        expect(out_stream.string).to include('Location Services denied')
      end

      it 'does not emit a denied-permission warning when authorization times out' do
        client.send(:handle_error, 'Location Services authorization timed out')
        expect(out_stream.string).to eq('')
      end

      it 'does not emit a denied-permission warning when authorization status is unknown' do
        client.send(:handle_error, 'Location Services authorization status is unknown')
        expect(out_stream.string).to eq('')
      end

      it 'logs non-location failures' do
        allow(client.instance_variable_get(:@verbose_proc)).to receive(:call).and_return(true)
        client.send(:handle_error, 'unexpected failure')
        expect(out_stream.string).to include('helper error: unexpected failure')
      end

      it 'ignores nil messages' do
        client.send(:handle_error, nil)
        expect(out_stream.string).to eq('')
      end
    end

    describe '#emit_location_warning' do
      it 'prints the warning only once' do
        client.send(:emit_location_warning)
        client.send(:emit_location_warning)
        occurrences = out_stream.string.scan('Location Services denied').size
        expect(occurrences).to eq(1)
      end
    end

    describe '#emit_install_failure' do
      it 'prints the failure message to the output stream' do
        client.send(:emit_install_failure, 'boom')
        expect(out_stream.string).to include('failed to install helper (boom)')
      end

      it 'includes reinstall guidance when an existing helper install is corrupt' do
        client.send(:emit_install_failure, 'boom', reinstall_required: true)
        expect(out_stream.string).to include('wifi-wand-macos-setup --reinstall')
      end
    end

    describe 'helper-backed calls after install failure' do
      subject(:client) do
        client_class.new(
          out_stream_proc:    -> { out_stream },
          verbose_proc:       -> { verbose_flag },
          macos_version_proc: -> { macos_version }
        )
      end

      let(:client_class) do
        Class.new(described_class) do
          attr_reader :execute_helper_command_calls

          def initialize(**kwargs)
            super
            @execute_helper_command_calls = 0
          end

          private def execute_helper_command(_command, **_kwargs)
            @execute_helper_command_calls += 1
            {
              stdout: '{"status":"ok","payload":{"ssid":"OfficeWiFi"}}',
              stderr: '',
              status: instance_double(Process::Status, success?: true),
            }
          end
        end
      end

      let(:status) { instance_double(Process::Status, success?: true) }

      before do
        allow(File).to receive(:executable?).with('/tmp/helper').and_return(false)
        allow(WifiWand::MacOsHelperBundle).to receive_messages(installed_executable_path: '/tmp/helper',
          helper_installed_and_valid?: false)
        allow(WifiWand::MacOsHelperBundle).to receive(:ensure_helper_installed).and_raise(StandardError,
          'boom')
      end

      it 'does not retry helper installation on a later helper-backed call in the same process' do
        first_result = client.connected_network_name
        second_result = client.scan_networks

        expect(first_result.payload).to be_nil
        expect(first_result.status).to eq(:unavailable)
        expect(second_result.payload).to eq([])
        expect(second_result.status).to eq(:unavailable)
        expect(WifiWand::MacOsHelperBundle).to have_received(:ensure_helper_installed).once
        expect(client.execute_helper_command_calls).to eq(0)
      end
    end

    describe '#log_verbose' do
      context 'when verbose mode is enabled' do
        let(:verbose_flag) { true }

        it 'prints the message with the helper prefix' do
          client.send(:log_verbose, 'details')
          expect(out_stream.string).to include('wifiwand helper: details')
        end
      end

      context 'when verbose mode is disabled' do
        let(:verbose_flag) { false }

        it 'does not print anything' do
          client.send(:log_verbose, 'details')
          expect(out_stream.string).to eq('')
        end
      end
    end

    describe '.sanitize_macos_version' do
      it 'keeps only numeric segments from versions with build metadata in parentheses' do
        expect(WifiWand::MacOsHelperBundle.sanitize_macos_version('15.6 (24A335)')).to eq('15.6')
      end

      it 'removes prerelease suffixes like beta tags' do
        expect(WifiWand::MacOsHelperBundle.sanitize_macos_version('15.6.1-beta2')).to eq('15.6.1')
      end

      it 'returns nil when the version does not include numeric components' do
        expect(WifiWand::MacOsHelperBundle.sanitize_macos_version('unknown')).to be_nil
      end
    end

    describe '.helper_supported_on_macos_version?' do
      it 'returns false below the minimum helper version' do
        expect(WifiWand::MacOsHelperBundle.helper_supported_on_macos_version?('13.6.1')).to be(false)
      end

      it 'returns true at the minimum helper version' do
        expect(WifiWand::MacOsHelperBundle.helper_supported_on_macos_version?('14.0')).to be(true)
      end

      it 'returns true above the minimum helper version with build metadata' do
        expect(WifiWand::MacOsHelperBundle.helper_supported_on_macos_version?('15.6 (24G84)')).to be(true)
      end

      it 'returns false when the version is missing' do
        expect(WifiWand::MacOsHelperBundle.helper_supported_on_macos_version?(nil)).to be(false)
      end

      it 'returns false when the version is malformed' do
        expect(WifiWand::MacOsHelperBundle.helper_supported_on_macos_version?('developer seed')).to be(false)
      end
    end

    describe '.helper_support_status_for_macos_version' do
      it 'parses the version once for callers that need status and diagnostics' do
        expect(WifiWand::MacOsHelperBundle).to receive(:parse_macos_version).with('developer seed').once
          .and_call_original

        status = WifiWand::MacOsHelperBundle.helper_support_status_for_macos_version('developer seed')
        expect(status).to be_unknown
      end
    end

    describe '.detect_macos_version' do
      let(:success_status) { instance_double(Process::Status, success?: true) }
      let(:failure_status) { instance_double(Process::Status, success?: false) }

      it 'returns the stripped sw_vers product version' do
        allow(Open3).to receive(:capture3).with('sw_vers', '-productVersion')
          .and_return(["15.6\n", '', success_status])

        expect(WifiWand::MacOsHelperBundle.detect_macos_version).to eq('15.6')
      end

      it 'returns nil when sw_vers exits successfully with empty output' do
        allow(Open3).to receive(:capture3).with('sw_vers', '-productVersion')
          .and_return(["\n", '', success_status])

        expect(WifiWand::MacOsHelperBundle.detect_macos_version).to be_nil
      end

      it 'returns nil when sw_vers exits unsuccessfully' do
        allow(Open3).to receive(:capture3).with('sw_vers', '-productVersion')
          .and_return(['', 'failed', failure_status])

        expect(WifiWand::MacOsHelperBundle.detect_macos_version).to be_nil
      end

      it 'returns nil when sw_vers is not available' do
        allow(Open3).to receive(:capture3).with('sw_vers', '-productVersion').and_raise(Errno::ENOENT)

        expect(WifiWand::MacOsHelperBundle.detect_macos_version).to be_nil
      end
    end
  end

  describe '.install_helper_bundle' do
    let(:installer) { WifiWand::MacOsHelperInstaller }
    let(:out_stream) { StringIO.new }
    let(:temp_dir) { Dir.mktmpdir('wifiwand-helper-install-spec') }
    let(:versioned_install_dir) { File.join(temp_dir, 'installed') }
    let(:installed_bundle_path) { File.join(versioned_install_dir, described_class::BUNDLE_NAME) }
    let(:installed_executable_path) do
      File.join(installed_bundle_path, 'Contents', 'MacOS', described_class::EXECUTABLE_NAME)
    end
    let(:source_bundle_path) { File.join(temp_dir, 'source', described_class::BUNDLE_NAME) }
    let(:source_executable_path) do
      File.join(source_bundle_path, 'Contents', 'MacOS', described_class::EXECUTABLE_NAME)
    end
    let(:source_code_resources_path) do
      File.join(source_bundle_path, 'Contents', '_CodeSignature', 'CodeResources')
    end
    let(:manifest_path) { File.join(versioned_install_dir, 'VERSION') }
    let(:install_manifest_path) do
      File.join(versioned_install_dir, described_class::MANIFEST_FILENAME)
    end

    before do
      allow(described_class).to receive_messages(
        versioned_install_dir:     versioned_install_dir,
        installed_bundle_path:     installed_bundle_path,
        installed_executable_path: installed_executable_path,
        source_bundle_path:        source_bundle_path,
        helper_version:            '9.9.9'
      )
      allow(installer).to receive(:run_bounded_helper_command) do |executable_path, command|
        script = File.read(executable_path)
        success = command == 'help' && !script.include?("exit 1\n")
        instance_double(
          Process::Status,
          success?:   success,
          exitstatus: success ? 0 : 1
        ).then do |status|
          {
            stdout: success ? 'wifiwand helper usage' : '',
            stderr: '',
            status: status,
          }
        end
      end

      create_helper_bundle(source_bundle_path, help_text: 'source helper')
    end

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'installs the helper via a staged copy and writes the version manifest' do
      described_class.install_helper_bundle(out_stream: out_stream)

      expect(described_class.helper_installed_and_valid?).to be(true)
      expect(File.symlink?(installed_bundle_path)).to be(true)
      expect(File.read(manifest_path)).to eq('9.9.9')
      expect(JSON.parse(File.read(install_manifest_path))).to include(
        'helper_version'     => '9.9.9',
        'bundle_fingerprint' => described_class.bundle_fingerprint(source_bundle_path)
      )
      expect(out_stream.string).to include('Installing wifiwand macOS helper...')
      expect(out_stream.string).to include('Helper bundle installed from pre-signed binary.')
    end

    it 'skips installation when the current helper is already valid' do
      described_class.install_helper_bundle(out_stream: nil)

      expect(installer).not_to receive(:stage_helper_bundle)

      described_class.install_helper_bundle(out_stream: out_stream)
      expect(out_stream.string).to be_empty
    end

    it 'force-installs even when the current helper is already valid' do
      described_class.install_helper_bundle(out_stream: nil)
      previous_release_path = described_class.resolved_installed_bundle_target

      allow(installer).to receive(:stage_helper_bundle).and_call_original

      described_class.install_helper_bundle(out_stream: out_stream, force: true)
      expect(installer).to have_received(:stage_helper_bundle).once
      expect(described_class.helper_installed_and_valid?).to be(true)
      expect(described_class.resolved_installed_bundle_target).not_to eq(previous_release_path)
      expect(out_stream.string).to include('Installing wifiwand macOS helper...')
      expect(out_stream.string).to include('Helper bundle installed from pre-signed binary.')
    end

    it 'does not publish a bundle when staged validation fails on first install' do
      File.write(source_executable_path, "#!/bin/sh\nexit 1\n")
      FileUtils.chmod(0o755, source_executable_path)

      expect do
        described_class.install_helper_bundle(out_stream: out_stream)
      end.to raise_error(RuntimeError, 'Staged helper installation failed validation.')

      expect(File).not_to exist(installed_bundle_path)
      expect(File).not_to exist(manifest_path)
    end

    it 'leaves the legacy bundle in place if executable migration fails' do
      create_helper_bundle(installed_bundle_path, help_text: 'existing helper')
      File.write(installed_executable_path, "#!/bin/sh\nexit 1\n")
      FileUtils.chmod(0o755, installed_executable_path)
      legacy_info_plist_path = File.join(installed_bundle_path, 'Contents', 'Info.plist')
      legacy_code_resources_path =
        File.join(installed_bundle_path, 'Contents', '_CodeSignature', 'CodeResources')
      original_info_plist = File.read(legacy_info_plist_path)
      original_code_resources = File.read(legacy_code_resources_path)

      allow(File).to receive(:rename).and_wrap_original do |original, source, destination|
        if source.include?('.link-') && destination == installed_executable_path
          raise StandardError, 'publish failed'
        end

        original.call(source, destination)
      end

      expect do
        described_class.install_helper_bundle(out_stream: out_stream)
      end.to raise_error(StandardError, 'publish failed')

      expect(File.read(installed_executable_path)).to eq("#!/bin/sh\nexit 1\n")
      expect(File.read(legacy_info_plist_path)).to eq(original_info_plist)
      expect(File.read(legacy_code_resources_path)).to eq(original_code_resources)
      expect(File).to exist(installed_bundle_path)
      expect(File).not_to exist(manifest_path)
    end

    it 'keeps installed_bundle_path visible while migrating a legacy install' do
      create_helper_bundle(installed_bundle_path, help_text: 'existing helper')
      File.write(installed_executable_path, "#!/bin/sh\nexit 1\n")
      FileUtils.chmod(0o755, installed_executable_path)

      observed_path_states = []

      allow(File).to receive(:rename).and_wrap_original do |original, source, destination|
        if source.include?('.link-') && destination == installed_executable_path
          observed_path_states << File.exist?(installed_bundle_path)
          observed_path_states << File.exist?(installed_executable_path)
        end

        original.call(source, destination)
      end

      described_class.install_helper_bundle(out_stream: nil)

      expect(observed_path_states).to eq([true, true])
      expect(File).to exist(installed_bundle_path)
      expect(File.symlink?(installed_bundle_path)).to be(false)
      expect(File.symlink?(installed_executable_path)).to be(true)
      expect(File.read(File.join(installed_bundle_path, 'Contents', '_CodeSignature', 'CodeResources')))
        .to eq(File.read(source_code_resources_path))
      expect(described_class.helper_installed_and_valid?).to be(true)
    end

    it 'keeps installed_bundle_path visible while replacing an existing symlinked install' do
      described_class.install_helper_bundle(out_stream: nil)

      File.write(installed_executable_path, "#!/bin/sh\nexit 1\n")
      FileUtils.chmod(0o755, installed_executable_path)

      observed_path_states = []

      allow(File).to receive(:rename).and_wrap_original do |original, source, destination|
        if source.include?('.link-') && destination == installed_bundle_path
          observed_path_states << File.exist?(installed_bundle_path)
          observed_path_states << File.symlink?(installed_bundle_path)
        end

        original.call(source, destination)
      end

      described_class.install_helper_bundle(out_stream: nil)

      expect(observed_path_states).to eq([true, true])
      expect(described_class.helper_installed_and_valid?).to be(true)
      expect(File.symlink?(installed_bundle_path)).to be(true)
    end

    it 'serializes concurrent first-run installs so only one copy executes' do
      installation_started = Queue.new
      allow(installer)
        .to receive(:stage_helper_bundle).and_wrap_original do |original, staged_bundle_path|
          installation_started << :started
          sleep(0.1)
          original.call(staged_bundle_path)
        end

      first_thread = Thread.new { described_class.install_helper_bundle(out_stream: nil) }
      installation_started.pop

      second_thread = Thread.new { described_class.install_helper_bundle(out_stream: nil) }

      [first_thread, second_thread].each(&:join)

      expect(installer).to have_received(:stage_helper_bundle).once
      expect(described_class.helper_installed_and_valid?).to be(true)
      expect(File.read(manifest_path)).to eq('9.9.9')
    end
  end

  describe '.run_bounded_helper_command' do
    let(:temp_dir) { Dir.mktmpdir('wifiwand-helper-run-spec') }
    let(:executable_path) { File.join(temp_dir, 'wifiwand-helper-test') }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'returns stdout, stderr, and status when the helper exits successfully' do
      write_helper_script(executable_path, <<~SH)
        #!/bin/sh
        echo "helper output"
        echo "helper warning" >&2
        exit 0
      SH

      result = described_class.run_bounded_helper_command(executable_path, 'help')

      expect(result[:stdout]).to eq("helper output\n")
      expect(result[:stderr]).to eq("helper warning\n")
      expect(result[:status]).to be_success
      expect(result[:status].exitstatus).to eq(0)
    end

    it 'uses a longer default timeout for scan-networks than for current-network' do
      expect(described_class.helper_command_timeout_seconds('scan-networks'))
        .to be > described_class.helper_command_timeout_seconds('current-network')
    end

    it 'calls on_timeout, terminates the helper, and returns nil when the helper hangs' do
      stub_const('WifiWand::MacOsHelperBundle::HELPER_TERMINATION_WAIT_SECONDS', 0.05)
      stub_const('WifiWand::MacOsHelperBundle::HELPER_OUTPUT_READER_JOIN_SECONDS', 0.05)
      write_helper_script(executable_path, <<~SH)
        #!/bin/sh
        trap 'exit 0' TERM
        echo "starting"
        echo "still running" >&2
        sleep 10
      SH
      timed_out = []

      result = described_class.run_bounded_helper_command(
        executable_path,
        'help',
        timeout_seconds: 0.05,
        on_timeout:      ->(command, timeout_seconds) { timed_out << [command, timeout_seconds] }
      )

      expect(result).to be_nil
      expect(timed_out).to eq([['help', 0.05]])
    end

    it 'does not leak stream cleanup IOErrors to stderr during timeout cleanup' do
      stub_const('WifiWand::MacOsHelperBundle::HELPER_TERMINATION_WAIT_SECONDS', 0.05)
      stub_const('WifiWand::MacOsHelperBundle::HELPER_OUTPUT_READER_JOIN_SECONDS', 0.05)
      write_helper_script(executable_path, <<~SH)
        #!/bin/sh
        trap 'exit 0' TERM
        sleep 10
      SH

      expect do
        described_class.run_bounded_helper_command(executable_path, 'help', timeout_seconds: 0.05)
      end.not_to output(/stream closed in another thread/).to_stderr
    end
  end

  describe '.helper_command_timeout_seconds' do
    it 'keeps current-network on the short default timeout' do
      expect(described_class.helper_command_timeout_seconds('current-network'))
        .to eq(described_class::DEFAULT_HELPER_COMMAND_TIMEOUT_SECONDS)
    end

    it 'gives scan-networks a longer default timeout' do
      expect(described_class.helper_command_timeout_seconds('scan-networks'))
        .to eq(described_class::SCAN_NETWORKS_HELPER_COMMAND_TIMEOUT_SECONDS)
    end
  end

  describe '.helper_bundle_valid?' do
    let(:installer) { WifiWand::MacOsHelperInstaller }
    let(:temp_dir) { Dir.mktmpdir('wifiwand-helper-valid-spec') }
    let(:bundle_path) { File.join(temp_dir, described_class::BUNDLE_NAME) }
    let(:executable_path) do
      File.join(bundle_path, 'Contents', 'MacOS', described_class::EXECUTABLE_NAME)
    end
    let(:info_plist_path) { File.join(bundle_path, 'Contents', 'Info.plist') }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    before do
      FileUtils.mkdir_p(File.dirname(executable_path))
      FileUtils.mkdir_p(File.dirname(info_plist_path))
      File.write(info_plist_path, '<plist version="1.0">helper</plist>')
    end

    it 'validates the helper with the help command expected by the shipped executable' do
      File.write(executable_path, <<~SH)
        #!/bin/sh
        if [ "$1" = "help" ]; then
          echo "wifiwand helper usage"
          exit 0
        fi
        echo "unknown command: $1" >&2
        exit 64
      SH
      FileUtils.chmod(0o755, executable_path)
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      expect(installer).to receive(:run_bounded_helper_command)
        .with(executable_path, 'help')
        .and_return(stdout: 'wifiwand helper usage', stderr: '', status: status)

      expect(described_class.helper_bundle_valid?(bundle_path)).to be(true)
    end

    it 'accepts successful help output written to stderr' do
      File.write(executable_path, "#!/bin/sh\nexit 0\n")
      FileUtils.chmod(0o755, executable_path)
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      expect(installer).to receive(:run_bounded_helper_command)
        .with(executable_path, 'help')
        .and_return(stdout: '', stderr: 'wifiwand helper usage', status: status)

      expect(described_class.helper_bundle_valid?(bundle_path)).to be(true)
    end

    it 'rejects successful probes that only emit incidental stderr noise' do
      File.write(executable_path, "#!/bin/sh\nexit 0\n")
      FileUtils.chmod(0o755, executable_path)
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      expect(installer).to receive(:run_bounded_helper_command)
        .with(executable_path, 'help')
        .and_return(stdout: '', stderr: 'stream closed in another thread', status: status)

      expect(described_class.helper_bundle_valid?(bundle_path)).to be(false)
    end

    it 'returns false when the helper validation probe times out' do
      File.write(executable_path, "#!/bin/sh\nexit 0\n")
      FileUtils.chmod(0o755, executable_path)
      allow(installer).to receive(:run_bounded_helper_command)
        .with(executable_path, 'help')
        .and_return(nil)

      expect(described_class.helper_bundle_valid?(bundle_path)).to be(false)
    end
  end

  describe '.helper_installed_and_valid?' do
    let(:installer) { WifiWand::MacOsHelperInstaller }
    let(:temp_dir) { Dir.mktmpdir('wifiwand-helper-current-spec') }
    let(:versioned_install_dir) { File.join(temp_dir, 'installed') }
    let(:installed_bundle_path) { File.join(versioned_install_dir, described_class::BUNDLE_NAME) }
    let(:installed_executable_path) do
      File.join(installed_bundle_path, 'Contents', 'MacOS', described_class::EXECUTABLE_NAME)
    end
    let(:source_bundle_path) { File.join(temp_dir, 'source', described_class::BUNDLE_NAME) }
    let(:install_manifest_path) do
      File.join(versioned_install_dir, described_class::MANIFEST_FILENAME)
    end

    before do
      allow(described_class).to receive_messages(
        versioned_install_dir:     versioned_install_dir,
        installed_bundle_path:     installed_bundle_path,
        installed_executable_path: installed_executable_path,
        source_bundle_path:        source_bundle_path,
        helper_version:            '9.9.9'
      )
      allow(installer).to receive(:run_bounded_helper_command) do |executable_path, command|
        script = File.read(executable_path)
        success = command == 'help' && !script.include?("exit 1\n")
        status = instance_double(Process::Status, success?: success, exitstatus: success ? 0 : 1)
        {
          stdout: success ? 'wifiwand helper usage' : '',
          stderr: '',
          status: status,
        }
      end
    end

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'returns false when a same-version installed helper differs from the shipped bundle' do
      create_helper_bundle(source_bundle_path, help_text: 'new helper')
      create_helper_bundle(installed_bundle_path, help_text: 'old helper')
      FileUtils.mkdir_p(versioned_install_dir)
      File.write(install_manifest_path, JSON.dump(
        'helper_version'     => '9.9.9',
        'bundle_fingerprint' => described_class.bundle_fingerprint(installed_bundle_path)
      ))

      expect(described_class.helper_bundle_valid?(installed_bundle_path)).to be(true)
      expect(described_class.helper_installed_and_valid?).to be(false)
    end
  end

  def create_helper_bundle(bundle_path, help_text:)
    executable_path = File.join(bundle_path, 'Contents', 'MacOS', described_class::EXECUTABLE_NAME)
    info_plist_path = File.join(bundle_path, 'Contents', 'Info.plist')
    code_resources_path = File.join(bundle_path, 'Contents', '_CodeSignature', 'CodeResources')

    FileUtils.mkdir_p(File.dirname(executable_path))
    File.write(executable_path, <<~SH)
      #!/bin/sh
      echo "#{help_text}"
      SH
    FileUtils.chmod(0o755, executable_path)

    FileUtils.mkdir_p(File.dirname(info_plist_path))
    File.write(info_plist_path, "<plist version=\"1.0\">#{help_text}</plist>")

    FileUtils.mkdir_p(File.dirname(code_resources_path))
    File.write(code_resources_path, "signature=#{help_text}\n")
  end

  def write_helper_script(executable_path, contents)
    File.write(executable_path, contents)
    FileUtils.chmod(0o755, executable_path)
  end
end
