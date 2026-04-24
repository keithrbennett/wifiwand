# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/status_line_data_builder'

class StatusLineDataBuilderSpecExpectedError < StandardError; end

describe WifiWand::StatusLineDataBuilder do
  let(:model) do
    double('model',
      wifi_on?:                   true,
      connected?:                 true,
      connected_network_name:     'HomeNetwork',
      internet_tcp_connectivity?: true,
      dns_working?:               true,
      captive_portal_state:       :free
    )
  end

  let(:progress_updates) { [] }
  let(:builder) do
    described_class.new(
      model,
      verbose:                             false,
      output:                              StringIO.new,
      worker_result_timeout_seconds:       0.05,
      worker_result_poll_interval_seconds: 0.001,
      worker_cleanup_timeout_seconds:      0.01
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

    it 'returns the wifi-off status without running internet checks' do
      allow(model).to receive(:wifi_on?).and_return(false)
      expect(model).not_to receive(:connected_network_name)
      expect(model).not_to receive(:connected?)
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
      output = StringIO.new
      failing_builder = described_class.new(model, verbose: true, output: output)
      allow(model).to receive(:wifi_on?).and_raise(WifiWand::Error, 'boom')

      result = failing_builder.call(progress_callback: ->(data) { progress_updates << data })

      expect(result).to be_nil
      expect(progress_updates).to eq([nil])
      expect(output.string).to include('Warning: status_line_data failed: WifiWand::Error: boom')
    end

    it 'reports connected with SSID unavailable when connected? is true but the SSID is nil' do
      allow(model).to receive_messages(connected?: true, connected_network_name: nil)

      result = builder.call

      expect(result[:connected]).to be(true)
      expect(result[:network_name]).to eq('[SSID unavailable]')
    end

    it 'reports disconnected when connected? is false and the SSID is nil' do
      allow(model).to receive_messages(connected?: false, connected_network_name: nil)

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

      allow(builder).to receive(:spawn_worker).and_wrap_original do |original, &block|
        thread = original.call(&block)
        thread.report_on_exception = false
        worker_threads << thread
        thread
      end

      allow(model).to receive(:connected?) do
        network_started << :started
        network_release.pop
        true
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

      allow(model).to receive(:connected?) do
        network_release.pop
        true
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

      allow(model).to receive(:connected?) do
        network_release.pop
        true
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
      output = StringIO.new
      failing_builder = described_class.new(
        model,
        verbose:                 true,
        output:                  output,
        expected_network_errors: [StatusLineDataBuilderSpecExpectedError]
      )
      allow(model).to receive(:connected?).and_raise(StatusLineDataBuilderSpecExpectedError, 'network down')

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
      expect(output.string).to include(
        'Warning: network status lookup failed: StatusLineDataBuilderSpecExpectedError: network down'
      )
    end

    it 'falls back gracefully when connectivity checks raise expected errors' do
      failing_builder = described_class.new(
        model,
        verbose:                 true,
        output:                  StringIO.new,
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
      network_release = Queue.new

      allow(model).to receive(:connected?) do
        network_release.pop
      end

      result = builder.call(progress_callback: ->(data) { progress_updates << data })

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
      expect(network_release.size).to eq(0)
    end

    it 'returns an indeterminate connectivity result when the connectivity worker never publishes a result' do
      connectivity_release = Queue.new

      allow(model).to receive(:internet_tcp_connectivity?) do
        connectivity_release.pop
      end

      result = builder.call(progress_callback: ->(data) { progress_updates << data })

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
      expect(connectivity_release.size).to eq(0)
    end

    it 'cleans up the sibling worker when one worker raises unexpectedly' do
      network_started = Queue.new
      network_release = Queue.new
      network_terminated = Queue.new
      worker_threads = []

      allow(builder).to receive(:spawn_worker).and_wrap_original do |original, &block|
        thread = original.call(&block)
        thread.report_on_exception = false
        worker_threads << thread
        thread
      end

      allow(model).to receive(:connected?) do
        network_started << :started
        network_release.pop
        true
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
        output:                              StringIO.new,
        worker_result_timeout_seconds:       0.005,
        worker_result_poll_interval_seconds: 0.001,
        worker_cleanup_timeout_seconds:      0.05
      )

      allow(model).to receive(:connected?) do
        sleep(0.02)
        true
      end
      expect(model).not_to receive(:connected_network_name)

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = slow_builder.call
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      expect(result).to include(
        wifi_on:        true,
        connected:      nil,
        network_name:   nil,
        dns_working:    true,
        internet_state: :reachable
      )
      expect(duration).to be < 0.08
    end

    it 'logs and forcefully terminates a worker that misses the cleanup timeout' do
      output = StringIO.new
      verbose_builder = described_class.new(
        model,
        verbose:                        true,
        output:                         output,
        worker_cleanup_timeout_seconds: 0.001
      )
      worker_release = Queue.new
      worker_terminated = Queue.new

      worker = Thread.new do
        worker_release.pop
      ensure
        worker_terminated << :terminated
      end
      worker.report_on_exception = false

      verbose_builder.send(:cleanup_worker_threads, worker)

      expect(output.string).to include('Warning: forcing worker thread termination after timeout')
      expect(worker_terminated.pop(timeout: 1)).to eq(:terminated)
      expect(worker).not_to be_alive
      expect(worker_release.size).to eq(0)
    end
  end
end
