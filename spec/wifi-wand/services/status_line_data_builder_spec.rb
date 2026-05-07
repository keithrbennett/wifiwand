# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/command_line_interface/output_formatter'
require_relative '../../../lib/wifi-wand/network_identity'
require_relative '../../../lib/wifi-wand/services/status_line_data_builder'

class StatusLineDataBuilderSpecExpectedError < StandardError; end

describe WifiWand::StatusLineDataBuilder do
  let(:model) do
    double('model',
      wifi_on?:                   true,
      status_wifi_on?:            true,
      status_network_identity:    { connected: true, network_name: 'HomeNetwork' },
      internet_tcp_connectivity?: true,
      dns_working?:               true,
      captive_portal_state:       :free
    )
  end

  let(:progress_updates) { [] }
  let(:builder) do
    described_class.new(model, verbose: false, out_stream: StringIO.new)
  end
  let(:fast_timeout_builder) do
    described_class.new(
      model,
      verbose:                                    false,
      out_stream:                                 StringIO.new,
      network_worker_result_timeout_seconds:      0.05,
      connectivity_worker_result_timeout_seconds: 0.05,
      worker_result_poll_interval_seconds:        0.001,
      worker_cleanup_timeout_seconds:             0.01
    )
  end
  let(:expected_initial_progress) do
    {
      wifi_on:                       true,
      dns_working:                   nil,
      internet_state:                :pending,
      internet_check_complete:       false,
      connected:                     :pending,
      network_name:                  :pending,
      captive_portal_state:          :indeterminate,
      captive_portal_login_required: :unknown,
    }
  end
  let(:expected_network_partial_progress) do
    {
      wifi_on:                       true,
      dns_working:                   nil,
      internet_state:                :pending,
      internet_check_complete:       false,
      connected:                     true,
      network_name:                  'HomeNetwork',
      captive_portal_state:          :indeterminate,
      captive_portal_login_required: :unknown,
    }
  end
  let(:expected_reachable_result) do
    {
      wifi_on:                       true,
      dns_working:                   true,
      connected:                     true,
      internet_state:                :reachable,
      internet_check_complete:       true,
      network_name:                  'HomeNetwork',
      captive_portal_state:          :free,
      captive_portal_login_required: :no,
    }
  end

  describe 'initialization' do
    it 'supports one-shot invocation through the class-level call method' do
      progress_callback = ->(_data) {}
      builder = instance_double(described_class)

      expect(described_class).to receive(:new).with(
        model,
        runtime_config: :runtime_config
      ).and_return(builder)
      expect(builder).to receive(:call).with(progress_callback: progress_callback).and_return({})

      described_class.call(
        model,
        progress_callback: progress_callback,
        runtime_config:    :runtime_config
      )
    end

    it 'uses the short default worker deadlines unless a caller overrides them' do
      default_builder = described_class.new(model)

      expect(default_builder.instance_variable_get(:@network_worker_result_timeout_seconds))
        .to eq(described_class::DEFAULT_NETWORK_WORKER_RESULT_TIMEOUT_SECONDS)
      expect(default_builder.instance_variable_get(:@connectivity_worker_result_timeout_seconds))
        .to eq(described_class::DEFAULT_CONNECTIVITY_WORKER_RESULT_TIMEOUT_SECONDS)
    end

    it 'reads out_stream from runtime config after initialization' do
      initial_output = StringIO.new
      updated_output = StringIO.new
      runtime_config = WifiWand::RuntimeConfig.new(verbose: false, out_stream: initial_output)
      builder = described_class.new(model, runtime_config: runtime_config)

      runtime_config.out_stream = updated_output

      expect(builder.out_stream).to eq(updated_output)
    end

    it 'prefers runtime config over explicit out_stream when runtime config is provided' do
      runtime_out_stream = StringIO.new
      runtime_config = WifiWand::RuntimeConfig.new(verbose: false, out_stream: runtime_out_stream)
      builder = described_class.new(model, runtime_config: runtime_config, out_stream: StringIO.new)

      expect(builder.out_stream).to eq(runtime_out_stream)
    end
  end

  describe '#call' do
    it 'builds full status data and streams partial updates' do
      result = builder.call(progress_callback: ->(data) { progress_updates << data })

      expect(result).to eq(expected_reachable_result)
      expect(progress_updates).to eq([
        expected_initial_progress,
        expected_network_partial_progress,
        expected_reachable_result,
      ])
    end

    it 'uses a bounded status wifi lookup before starting workers' do
      expect(model).not_to receive(:wifi_on?)
      expect(model).to receive(:status_wifi_on?) do |timeout_in_secs:|
        expect(timeout_in_secs).to be_positive
        expect(timeout_in_secs).to be <= described_class::DEFAULT_NETWORK_WORKER_RESULT_TIMEOUT_SECONDS
        true
      end

      result = builder.call

      expect(result).to eq(expected_reachable_result)
    end

    it 'returns the wifi-off status without running internet checks' do
      allow(model).to receive(:status_wifi_on?).and_return(false)
      expect(model).not_to receive(:status_network_identity)
      expect(model).not_to receive(:internet_tcp_connectivity?)

      result = builder.call

      expect(result).to eq(
        wifi_on:                       false,
        dns_working:                   false,
        connected:                     false,
        internet_state:                :unreachable,
        internet_check_complete:       true,
        network_name:                  nil,
        captive_portal_state:          :indeterminate,
        captive_portal_login_required: :no
      )
    end

    it 'marks captive portal login required when portal detection succeeds' do
      allow(model).to receive_messages(
        internet_tcp_connectivity?: true,
        dns_working?:               true,
        captive_portal_state:       :present
      )

      result = builder.call

      expect(result[:dns_working]).to be true
      expect(result[:internet_state]).to eq(:unreachable)
      expect(result[:captive_portal_state]).to eq(:present)
      expect(result[:captive_portal_login_required]).to eq(:yes)
    end

    it 'preserves an indeterminate captive portal result when TCP and DNS succeed' do
      allow(model).to receive_messages(
        internet_tcp_connectivity?: true,
        dns_working?:               true,
        captive_portal_state:       :indeterminate
      )

      result = builder.call

      expect(result[:dns_working]).to be true
      expect(result[:internet_state]).to eq(:indeterminate)
      expect(result[:internet_check_complete]).to be true
      expect(result[:captive_portal_state]).to eq(:indeterminate)
      expect(result[:captive_portal_login_required]).to eq(:unknown)
    end

    it 'marks captive portal login as unknown when TCP or DNS fails' do
      allow(model).to receive_messages(internet_tcp_connectivity?: false, dns_working?: false)

      result = builder.call

      expect(result[:dns_working]).to be false
      expect(result[:internet_state]).to eq(:unreachable)
      expect(result[:internet_check_complete]).to be true
      expect(result[:captive_portal_state]).to eq(:indeterminate)
      expect(result[:captive_portal_login_required]).to eq(:unknown)
    end

    it 'preserves successful DNS status when TCP connectivity fails' do
      allow(model).to receive_messages(internet_tcp_connectivity?: false, dns_working?: true)

      result = builder.call

      expect(result[:dns_working]).to be true
      expect(result[:internet_state]).to eq(:unreachable)
      expect(result[:internet_check_complete]).to be true
      expect(result[:captive_portal_state]).to eq(:indeterminate)
      expect(result[:captive_portal_login_required]).to eq(:unknown)
    end

    it 'returns nil and emits a nil progress update when the initial wifi check fails' do
      out_stream = StringIO.new
      failing_builder = described_class.new(model, verbose: true, out_stream: out_stream)
      allow(model).to receive(:status_wifi_on?).and_raise(WifiWand::Error, 'boom')

      result = failing_builder.call(progress_callback: ->(data) { progress_updates << data })

      expect(result).to be_nil
      expect(progress_updates).to eq([nil])
      expect(out_stream.string).to include('Warning: status_line_data failed: WifiWand::Error: boom')
    end

    it 'reports connected with a nil SSID when status identity is connected but the SSID is nil' do
      allow(model).to receive(:status_network_identity).and_return(connected: true, network_name: nil)

      result = builder.call

      expect(result[:connected]).to be(true)
      expect(result[:network_name]).to be_nil
    end

    it 'reports disconnected when status identity raises a WiFi error' do
      allow(model).to receive(:status_network_identity).and_raise(WifiWand::Error, 'lookup failed')

      result = builder.call

      expect(result[:connected]).to be(false)
      expect(result[:network_name]).to be_nil
    end

    it 'reports unknown network data when status identity raises a command error' do
      command_error = WifiWand::CommandExecutor::OsCommandError.new(
        result: command_result(stderr: 'aborted', exitstatus: nil, termsig: 6, command: 'nmcli radio wifi')
      )
      allow(model).to receive(:status_network_identity).and_raise(command_error)

      result = builder.call

      expect(result[:connected]).to be_nil
      expect(result[:network_name]).to be_nil
    end

    it 'reports unknown network data when status identity cannot start a command' do
      allow(model).to receive(:status_network_identity)
        .and_raise(WifiWand::CommandSpawnError.new(
          command: 'nmcli radio wifi',
          reason:  'Resource temporarily unavailable'
        ))

      result = builder.call

      expect(result[:connected]).to be_nil
      expect(result[:network_name]).to be_nil
    end

    it 'logs a network identity warning in verbose mode without raising' do
      out_stream = StringIO.new
      verbose_builder = described_class.new(
        model,
        verbose:    true,
        out_stream: out_stream
      )
      allow(model).to receive(:status_network_identity).and_raise(WifiWand::Error, 'lookup failed')

      result = verbose_builder.call

      expect(result[:connected]).to be(false)
      expect(result[:network_name]).to be_nil
      expect(out_stream.string).to include(
        'Warning: network status lookup failed: WifiWand::Error: lookup failed'
      )
    end

    it 'renders a redacted associated network as a yellow unavailable placeholder' do
      formatter = Class.new do
        include WifiWand::CommandLineInterface::OutputFormatter

        attr_reader :out_stream

        def initialize
          @out_stream = StringIO.new
        end
      end.new
      allow(formatter.out_stream).to receive(:tty?).and_return(true)
      allow(model).to receive(:status_network_identity).and_return(connected: true, network_name: nil)

      result = builder.call
      rendered_status = formatter.status_line(result)

      unavailable_label = WifiWand::NetworkIdentity::SSID_UNAVAILABLE_LABEL

      expect(rendered_status).to include("\e[33m#{unavailable_label}\e[0m")
      expect(rendered_status).not_to include("\e[36m#{unavailable_label}\e[0m")
    end

    it 'reports disconnected when status identity is disconnected and the SSID is nil' do
      allow(model).to receive(:status_network_identity).and_return(connected: false, network_name: nil)

      result = builder.call

      expect(result[:connected]).to be(false)
      expect(result[:network_name]).to be_nil
    end

    it 'starts both workers before either finishes' do
      network_started = Queue.new
      connectivity_started = Queue.new
      network_release = Queue.new
      connectivity_release = Queue.new
      worker_threads = []

      allow(builder).to receive(:spawn_worker).and_wrap_original do |original, *args, &block|
        thread = original.call(*args, &block)
        thread.report_on_exception = false
        worker_threads << thread
        thread
      end

      allow(model).to receive(:status_network_identity) do
        network_started << :started
        network_release.pop
        { connected: true, network_name: 'HomeNetwork' }
      end
      allow(model).to receive(:internet_tcp_connectivity?) do
        connectivity_started << :started
        connectivity_release.pop
        true
      end

      caller_thread = Thread.new { builder.call }

      expect(network_started.pop(timeout: 1)).to eq(:started)
      expect(connectivity_started.pop(timeout: 1)).to eq(:started)

      network_release << :continue
      connectivity_release << :continue

      result = caller_thread.value

      expect(result).to eq(expected_reachable_result)
      expect(worker_threads.size).to eq(2)
      expect(worker_threads).to all(satisfy { |thread| !thread.alive? })
    end

    it 'keeps the intermediate callback network-only when connectivity finishes first' do
      network_release = Queue.new
      connectivity_finished = Queue.new

      allow(model).to receive(:status_network_identity) do
        network_release.pop
        { connected: true, network_name: 'HomeNetwork' }
      end
      allow(model).to receive(:dns_working?) do
        connectivity_finished << :done
        true
      end

      caller_thread = Thread.new do
        builder.call(progress_callback: ->(data) { progress_updates << data })
      end

      expect(connectivity_finished.pop(timeout: 1)).to eq(:done)
      expect(progress_updates).to eq([expected_initial_progress])

      network_release << :continue

      result = caller_thread.value

      expect(result).to eq(expected_reachable_result)
      expect(progress_updates).to eq([
        expected_initial_progress,
        expected_network_partial_progress,
        expected_reachable_result,
      ])
    end

    it 'emits the network partial before re-raising an earlier connectivity failure' do
      network_release = Queue.new
      connectivity_failed = Queue.new

      allow(model).to receive(:status_network_identity) do
        network_release.pop
        { connected: true, network_name: 'HomeNetwork' }
      end
      allow(model).to receive(:captive_portal_state) do
        connectivity_failed << :failed
        raise 'boom'
      end

      caller_thread = Thread.new do
        builder.call(progress_callback: ->(data) { progress_updates << data })
      end
      caller_thread.report_on_exception = false

      expect(connectivity_failed.pop(timeout: 1)).to eq(:failed)
      expect(progress_updates).to eq([expected_initial_progress])

      network_release << :continue

      expect { caller_thread.value }.to raise_error(RuntimeError, 'boom')
      expect(progress_updates).to eq([
        expected_initial_progress,
        expected_network_partial_progress,
      ])
    end

    it 'falls back gracefully when network identity raises an expected error' do
      out_stream = StringIO.new
      failing_builder = described_class.new(
        model,
        verbose:                 true,
        out_stream:              out_stream,
        expected_network_errors: [StatusLineDataBuilderSpecExpectedError]
      )
      allow(model).to receive(:status_network_identity)
        .and_raise(StatusLineDataBuilderSpecExpectedError, 'network down')

      result = failing_builder.call

      expect(result).to eq(
        wifi_on:                       true,
        dns_working:                   true,
        connected:                     false,
        internet_state:                :reachable,
        internet_check_complete:       true,
        network_name:                  nil,
        captive_portal_state:          :free,
        captive_portal_login_required: :no
      )
      expect(out_stream.string).to include(
        'Warning: network status lookup failed: StatusLineDataBuilderSpecExpectedError: network down'
      )
    end

    it 'raises when bounded network identity is not implemented' do
      out_stream = StringIO.new
      failing_builder = described_class.new(model, verbose: true, out_stream: out_stream)
      allow(model).to receive(:status_network_identity)
        .and_raise(WifiWand::MethodNotImplementedError)

      expect do
        failing_builder.call(progress_callback: ->(data) { progress_updates << data })
      end.to raise_error(WifiWand::MethodNotImplementedError)
      expect(progress_updates).to eq([expected_initial_progress])
      expect(out_stream.string).to be_empty
    end

    it 'raises when network identity reports a missing dependency' do
      out_stream = StringIO.new
      failing_builder = described_class.new(model, verbose: true, out_stream: out_stream)
      allow(model).to receive(:status_network_identity)
        .and_raise(WifiWand::CommandNotFoundError.new('iw (install: sudo apt install iw)'))

      expect do
        failing_builder.call(progress_callback: ->(data) { progress_updates << data })
      end.to raise_error(WifiWand::CommandNotFoundError, /iw/)
      expect(progress_updates).to eq([expected_initial_progress])
      expect(out_stream.string).to be_empty
    end

    it 'falls back gracefully when connectivity checks raise expected errors' do
      failing_builder = described_class.new(
        model,
        verbose:                 true,
        out_stream:              StringIO.new,
        expected_network_errors: [StatusLineDataBuilderSpecExpectedError]
      )
      allow(model).to receive(:internet_tcp_connectivity?).and_raise(
        StatusLineDataBuilderSpecExpectedError,
        'tcp down'
      )
      allow(model).to receive(:dns_working?).and_raise(StatusLineDataBuilderSpecExpectedError, 'dns down')

      result = failing_builder.call

      expect(result).to eq(
        wifi_on:                       true,
        dns_working:                   false,
        connected:                     true,
        internet_state:                :unreachable,
        internet_check_complete:       true,
        network_name:                  'HomeNetwork',
        captive_portal_state:          :indeterminate,
        captive_portal_login_required: :unknown
      )
    end

    it 'returns partial connectivity data when the network worker never publishes a result' do
      allow(model).to receive(:status_network_identity) do |timeout_in_secs:|
        sleep(timeout_in_secs)
        raise WifiWand::CommandTimeoutError.new(
          command:         'status network identity',
          timeout_in_secs: timeout_in_secs
        )
      end

      result = fast_timeout_builder.call(progress_callback: ->(data) { progress_updates << data })

      expect(result).to eq(
        wifi_on:                       true,
        dns_working:                   true,
        connected:                     nil,
        internet_state:                :reachable,
        internet_check_complete:       true,
        network_name:                  nil,
        captive_portal_state:          :free,
        captive_portal_login_required: :no
      )
      expect(progress_updates).to eq([
        expected_initial_progress,
        expected_initial_progress.merge(connected: nil, network_name: nil),
        result,
      ])
    end

    it 'uses a bounded status network identity lookup before falling back on timeout' do
      bounded_model = Class.new do
        attr_reader :network_identity_timeouts

        def initialize
          @network_identity_active = false
          @network_identity_timeouts = []
        end

        def status_wifi_on?(timeout_in_secs:) = true

        define_method(:internet_tcp_connectivity?) do |timeout_in_secs:, return_details:|
          { success: true, timed_out: false }
        end

        define_method(:dns_working?) do |timeout_in_secs:, return_details:|
          { success: true, timed_out: false }
        end

        def captive_portal_state(timeout_in_secs:) = :free

        def status_network_identity(timeout_in_secs:)
          @network_identity_timeouts << timeout_in_secs
          @network_identity_active = true
          sleep(timeout_in_secs)
          raise WifiWand::CommandTimeoutError.new(
            command:         'status network identity',
            timeout_in_secs: timeout_in_secs
          )
        ensure
          @network_identity_active = false
        end

        def network_identity_active? = @network_identity_active
      end.new
      bounded_builder = described_class.new(
        bounded_model,
        out_stream:                                 StringIO.new,
        network_worker_result_timeout_seconds:      0.02,
        connectivity_worker_result_timeout_seconds: 0.05,
        worker_result_poll_interval_seconds:        0.001,
        worker_cleanup_timeout_seconds:             0.05
      )

      result = nil
      Timeout.timeout(1) { result = bounded_builder.call }

      expect(result).to include(
        wifi_on:      true,
        connected:    nil,
        network_name: nil
      )
      expect(bounded_model.network_identity_timeouts.first).to be_between(0, 0.02).exclusive
      expect(bounded_model.network_identity_active?).to be(false)
    end

    it 'returns an indeterminate connectivity result when the connectivity worker never publishes a result' do
      allow(model).to receive(:internet_tcp_connectivity?) do |timeout_in_secs:, return_details:|
        expect(return_details).to be true
        sleep(timeout_in_secs)
        { success: false, timed_out: true }
      end

      result = fast_timeout_builder.call(progress_callback: ->(data) { progress_updates << data })

      expect(result).to eq(
        wifi_on:                       true,
        dns_working:                   nil,
        connected:                     true,
        internet_state:                :indeterminate,
        internet_check_complete:       true,
        network_name:                  'HomeNetwork',
        captive_portal_state:          :indeterminate,
        captive_portal_login_required: :unknown
      )
      expect(progress_updates).to eq([
        expected_initial_progress,
        expected_network_partial_progress,
        result,
      ])
    end

    it 'falls back network data independently when the connectivity timeout is longer' do
      split_timeout_builder = described_class.new(
        model,
        out_stream:                                 StringIO.new,
        network_worker_result_timeout_seconds:      0.005,
        connectivity_worker_result_timeout_seconds: 0.05,
        worker_result_poll_interval_seconds:        0.001,
        worker_cleanup_timeout_seconds:             0.05
      )

      allow(model).to receive(:status_network_identity) do |timeout_in_secs:|
        sleep(timeout_in_secs)
        raise WifiWand::CommandTimeoutError.new(
          command:         'status network identity',
          timeout_in_secs: timeout_in_secs
        )
      end

      result = nil
      Timeout.timeout(1) do
        result = split_timeout_builder.call(progress_callback: ->(data) { progress_updates << data })
      end

      expect(result).to eq(
        wifi_on:                       true,
        dns_working:                   true,
        connected:                     nil,
        internet_state:                :reachable,
        internet_check_complete:       true,
        network_name:                  nil,
        captive_portal_state:          :free,
        captive_portal_login_required: :no
      )
      expect(progress_updates).to eq([
        expected_initial_progress,
        expected_initial_progress.merge(connected: nil, network_name: nil),
        result,
      ])
    end

    it 'returns fallback data when both workers stay blocked past their own deadlines' do
      overall_bounded_builder = described_class.new(
        model,
        out_stream:                                 StringIO.new,
        network_worker_result_timeout_seconds:      0.02,
        connectivity_worker_result_timeout_seconds: 0.05,
        worker_result_poll_interval_seconds:        0.001,
        worker_cleanup_timeout_seconds:             0.005
      )
      network_started = Queue.new
      connectivity_started = Queue.new

      allow(model).to receive(:status_network_identity) do |timeout_in_secs:|
        network_started << :started
        sleep(timeout_in_secs)
        raise WifiWand::CommandTimeoutError.new(
          command:         'status network identity',
          timeout_in_secs: timeout_in_secs
        )
      end
      allow(model).to receive(:internet_tcp_connectivity?) do |timeout_in_secs:, return_details:|
        expect(return_details).to be true
        connectivity_started << :started
        sleep(timeout_in_secs)
        { success: false, timed_out: true }
      end

      result = nil
      Timeout.timeout(1) do
        result = overall_bounded_builder.call(progress_callback: ->(data) { progress_updates << data })
      end

      expect(result).to eq(
        wifi_on:                       true,
        dns_working:                   nil,
        connected:                     nil,
        internet_state:                :indeterminate,
        internet_check_complete:       true,
        network_name:                  nil,
        captive_portal_state:          :indeterminate,
        captive_portal_login_required: :unknown
      )
      expect(progress_updates).to eq([
        expected_initial_progress,
        expected_initial_progress.merge(connected: nil, network_name: nil),
        result,
      ])
      expect(network_started.pop(timeout: 1)).to eq(:started)
      expect(connectivity_started.pop(timeout: 1)).to eq(:started)
    end

    it 'tracks an end-to-end worker stuck inside a model call after returning fallback data' do
      out_stream = StringIO.new
      stuck_worker_builder = described_class.new(
        model,
        verbose:                                    true,
        out_stream:                                 out_stream,
        network_worker_result_timeout_seconds:      0.005,
        connectivity_worker_result_timeout_seconds: 0.05,
        worker_result_poll_interval_seconds:        0.001,
        worker_cleanup_timeout_seconds:             0.001
      )
      network_release = Queue.new
      network_terminated = Queue.new

      allow(model).to receive(:status_network_identity) do
        network_release.pop
        { connected: true, network_name: 'HomeNetwork' }
      ensure
        network_terminated << :terminated
      end

      result = nil
      Timeout.timeout(1) { result = stuck_worker_builder.call }

      stragglers = stuck_worker_builder.instance_variable_get(:@straggler_threads)
      expect(result).to include(
        wifi_on:      true,
        connected:    nil,
        network_name: nil
      )
      expect(out_stream.string).to include('Warning: worker thread still running after cancellation request')
      expect(stragglers.size).to eq(1)
      straggler = stragglers.first
      expect(straggler).to be_alive

      network_release << :continue
      expect(network_terminated.pop(timeout: 1)).to eq(:terminated)

      stuck_worker_builder.send(:reap_straggler_threads)

      expect(straggler).not_to be_alive
      expect(stuck_worker_builder.instance_variable_get(:@straggler_threads)).to be_empty
    end

    it 'cleans up the sibling worker when one worker raises unexpectedly' do
      network_started = Queue.new
      network_release = Queue.new
      network_terminated = Queue.new
      worker_threads = []

      allow(builder).to receive(:spawn_worker).and_wrap_original do |original, *args, &block|
        thread = original.call(*args, &block)
        thread.report_on_exception = false
        worker_threads << thread
        thread
      end

      allow(model).to receive(:status_network_identity) do
        network_started << :started
        network_release.pop
        { connected: true, network_name: 'HomeNetwork' }
      ensure
        network_terminated << :terminated
      end
      allow(model).to receive(:internet_tcp_connectivity?) do
        started = network_started.pop(timeout: 1)
        raise 'network worker did not start' unless started == :started

        true
      end
      allow(model).to receive(:captive_portal_state).and_raise(RuntimeError, 'boom')

      caller_thread = Thread.new { builder.call }
      caller_thread.report_on_exception = false

      network_release << :continue

      expect { caller_thread.value }.to raise_error(RuntimeError, 'boom')
      expect(network_terminated.pop(timeout: 1)).to eq(:terminated)

      expect(worker_threads.size).to eq(2)
      expect(worker_threads).to all(satisfy { |thread| !thread.alive? })
    end
  end

  describe '#cleanup_worker_threads' do
    it 'cancels follow-up work so cleanup stays bounded when a worker is merely slow' do
      slow_builder = described_class.new(
        model,
        out_stream:                                 StringIO.new,
        network_worker_result_timeout_seconds:      0.005,
        connectivity_worker_result_timeout_seconds: 0.05,
        worker_result_poll_interval_seconds:        0.001,
        worker_cleanup_timeout_seconds:             0.05
      )

      allow(model).to receive(:status_network_identity) do
        sleep(0.02)
        { connected: true, network_name: 'HomeNetwork' }
      end

      result = nil
      Timeout.timeout(1) { result = slow_builder.call }

      expect(result).to include(
        wifi_on:        true,
        connected:      nil,
        network_name:   nil,
        dns_working:    true,
        internet_state: :reachable
      )
    end

    it 'waits for a registered bounded worker to exit without forcefully terminating it' do
      out_stream = StringIO.new
      verbose_builder = described_class.new(
        model,
        verbose:                        true,
        out_stream:                     out_stream,
        worker_cleanup_timeout_seconds: 0.001
      )
      worker_terminated = Queue.new

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.05
      worker = verbose_builder.send(:spawn_worker, :network, deadline) do
        sleep(0.02)
      ensure
        worker_terminated << :terminated
      end
      allow(worker).to receive(:kill)

      verbose_builder.send(:cleanup_worker_threads, worker)

      expect(out_stream.string).to be_empty
      expect(worker).not_to have_received(:kill)
      expect(worker_terminated.pop(timeout: 1)).to eq(:terminated)
      expect(worker).not_to be_alive
    end

    it 'tracks a worker that violates its registered timeout until it exits' do
      out_stream = StringIO.new
      verbose_builder = described_class.new(
        model,
        verbose:                        true,
        out_stream:                     out_stream,
        worker_cleanup_timeout_seconds: 0.001
      )
      worker_release = Queue.new
      worker_terminated = Queue.new

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      worker = verbose_builder.send(:spawn_worker, :network, deadline) do
        worker_release.pop
      ensure
        worker_terminated << :terminated
      end
      allow(worker).to receive(:kill)

      verbose_builder.send(:cleanup_worker_threads, worker)

      expect(out_stream.string).to include('Warning: worker thread still running after cancellation request')
      expect(worker).to be_alive
      expect(worker).not_to have_received(:kill)
      expect(verbose_builder.instance_variable_get(:@straggler_threads)).to include(worker)

      worker_release << :continue
      expect(worker_terminated.pop(timeout: 1)).to eq(:terminated)

      verbose_builder.send(:reap_straggler_threads)

      expect(worker).not_to be_alive
      expect(verbose_builder.instance_variable_get(:@straggler_threads)).not_to include(worker)
    end

    it 'lets cooperative workers observe cancellation and clean up resources' do
      worker_terminated = Queue.new
      worker = Thread.new do
        sleep(0.001) until builder.send(:cancelled?)
      ensure
        worker_terminated << :terminated
      end
      worker.report_on_exception = false

      builder.send(:cleanup_worker_threads, worker)

      expect(worker_terminated.pop(timeout: 1)).to eq(:terminated)
      expect(worker).not_to be_alive
    end
  end

  describe 'private worker fallbacks' do
    it 'raises a clear error for an unknown worker timeout lookup' do
      expect { builder.send(:worker_result_timeout_seconds_for, :other) }
        .to raise_error(ArgumentError, 'Unknown worker name: other')
    end

    it 'returns an empty fallback payload for an unknown worker name' do
      expect(builder.send(:fallback_worker_result, :other)).to eq({})
    end

    it 'uses connectivity fallback data when cancellation is observed' do
      expect(builder.send(:cancelled_worker_result, :connectivity)).to eq(
        dns_working:                   nil,
        internet_state:                :indeterminate,
        internet_check_complete:       true,
        captive_portal_state:          :indeterminate,
        captive_portal_login_required: :unknown
      )
    end

    it 'treats captive portal lookup failures as indeterminate connectivity' do
      allow(model).to receive(:captive_portal_state).and_raise(WifiWand::Error, 'portal failed')

      expect(builder.send(:captive_portal_state, timeout_in_secs: 0.01)).to eq(:indeterminate)
    end
  end
end
