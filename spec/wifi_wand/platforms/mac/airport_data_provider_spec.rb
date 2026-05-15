# frozen_string_literal: true

require 'json'
require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/platforms/mac/airport_data_provider'

module WifiWand
  describe Platforms::Mac::AirportDataProvider do
    subject(:provider) do
      described_class.new(
        owner:          owner,
        command_runner: command_runner
      )
    end

    let(:owner) { Object.new }
    let(:command_runner) { double('command_runner') }

    describe '#data' do
      it 'parses system_profiler JSON output' do
        json_output = '{"SPAirPortDataType": [{"test": "data"}]}'
        allow(command_runner).to receive(:call).with(
          described_class::SYSTEM_PROFILER_AIRPORT_ARGS,
          raise_on_error:  true,
          timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
        ).and_return(command_result(stdout: json_output))

        expect(provider.data).to eq({ 'SPAirPortDataType' => [{ 'test' => 'data' }] })
      end

      it 'raises a system profiler error for invalid JSON' do
        allow(command_runner).to receive(:call).and_return(command_result(stdout: 'invalid json'))

        expect { provider.data }.to raise_error(/Failed to parse system_profiler output/)
      end

      it 'passes an explicit timeout to system_profiler' do
        json_output = '{"SPAirPortDataType": [{"test": "data"}]}'

        expect(command_runner).to receive(:call).with(
          described_class::SYSTEM_PROFILER_AIRPORT_ARGS,
          raise_on_error:  true,
          timeout_in_secs: 2.5
        ).and_return(command_result(stdout: json_output))

        expect(provider.data(timeout_in_secs: 2.5)).to eq({ 'SPAirPortDataType' => [{ 'test' => 'data' }] })
      end

      it 'allows command execution errors to report unavailable profiler data' do
        error = WifiWand::CommandNotFoundError.new('system_profiler')

        allow(command_runner).to receive(:call).and_raise(error)

        expect { provider.data }.to raise_error(error)
      end

      it 'memoizes parsed system_profiler data only within a cache scope' do
        first_json_output = '{"SPAirPortDataType": [{"test": "first"}]}'
        second_json_output = '{"SPAirPortDataType": [{"test": "second"}]}'

        expect(command_runner).to receive(:call).with(
          described_class::SYSTEM_PROFILER_AIRPORT_ARGS,
          raise_on_error:  true,
          timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
        ).twice.and_return(
          command_result(stdout: first_json_output),
          command_result(stdout: second_json_output)
        )

        provider.with_cache_scope do
          2.times do
            expect(provider.data).to eq({ 'SPAirPortDataType' => [{ 'test' => 'first' }] })
          end
        end

        provider.with_cache_scope do
          expect(provider.data).to eq({ 'SPAirPortDataType' => [{ 'test' => 'second' }] })
        end
      end

      it 'does not memoize parsed system_profiler data outside a cache scope' do
        first_json_output = '{"SPAirPortDataType": [{"test": "first"}]}'
        second_json_output = '{"SPAirPortDataType": [{"test": "second"}]}'

        expect(command_runner).to receive(:call).with(
          described_class::SYSTEM_PROFILER_AIRPORT_ARGS,
          raise_on_error:  true,
          timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
        ).twice.and_return(
          command_result(stdout: first_json_output),
          command_result(stdout: second_json_output)
        )

        expect(provider.data).to eq({ 'SPAirPortDataType' => [{ 'test' => 'first' }] })
        expect(provider.data).to eq({ 'SPAirPortDataType' => [{ 'test' => 'second' }] })
      end
    end

    describe '#with_cache_scope' do
      it 'reuses one scoped snapshot across nested cache scopes' do
        json_output = '{"SPAirPortDataType": [{"test": "nested"}]}'

        expect(command_runner).to receive(:call).once.and_return(command_result(stdout: json_output))

        provider.with_cache_scope do
          expect(provider.data).to eq({ 'SPAirPortDataType' => [{ 'test' => 'nested' }] })

          provider.with_cache_scope do
            expect(provider.data).to eq({ 'SPAirPortDataType' => [{ 'test' => 'nested' }] })
          end

          expect(provider.active_cache_context).not_to be_nil
        end

        expect(provider.active_cache_context).to be_nil
      end

      it 'keeps scoped airport snapshots isolated by owner identity' do
        other_provider = described_class.new(
          owner:          Object.new,
          command_runner: command_runner
        )
        first_json_output = '{"SPAirPortDataType": [{"test": "first-owner"}]}'
        second_json_output = '{"SPAirPortDataType": [{"test": "second-owner"}]}'

        expect(command_runner).to receive(:call).twice.and_return(
          command_result(stdout: first_json_output),
          command_result(stdout: second_json_output)
        )

        provider.with_cache_scope do
          other_provider.with_cache_scope do
            expect(provider.data).to eq({ 'SPAirPortDataType' => [{ 'test' => 'first-owner' }] })
            expect(other_provider.data).to eq({ 'SPAirPortDataType' => [{ 'test' => 'second-owner' }] })
            expect(provider.data).to eq({ 'SPAirPortDataType' => [{ 'test' => 'first-owner' }] })
            expect(other_provider.data).to eq({ 'SPAirPortDataType' => [{ 'test' => 'second-owner' }] })
          end
        end
      end

      it 'cleans cache context after a cache scope exits' do
        provider.with_cache_scope do
          expect(provider.active_cache_context).not_to be_nil
        end

        expect(provider.active_cache_context).to be_nil
      end

      it 'keeps scoped airport snapshots isolated by thread' do
        payloads = {
          'first'  => JSON.generate('SPAirPortDataType' => [{ 'test' => 'first' }]),
          'second' => JSON.generate('SPAirPortDataType' => [{ 'test' => 'second' }]),
        }
        calls = Queue.new

        allow(command_runner).to receive(:call) do
          thread_name = Thread.current[:wifi_wand_airport_cache_spec_name]
          calls << thread_name
          command_result(stdout: payloads.fetch(thread_name))
        end

        results = %w[first second].map do |thread_name|
          Thread.new do
            Thread.current[:wifi_wand_airport_cache_spec_name] = thread_name
            provider.with_cache_scope do
              [provider.data, provider.data]
            end
          end
        end.map(&:value)

        expect(results).to contain_exactly(
          [
            { 'SPAirPortDataType' => [{ 'test' => 'first' }] },
            { 'SPAirPortDataType' => [{ 'test' => 'first' }] },
          ],
          [
            { 'SPAirPortDataType' => [{ 'test' => 'second' }] },
            { 'SPAirPortDataType' => [{ 'test' => 'second' }] },
          ]
        )
        expect(calls.size).to eq(2)
      end
    end

    describe '#invalidate_cache' do
      it 'refreshes an active scoped snapshot after another thread invalidates airport data' do
        first_json_output = '{"SPAirPortDataType": [{"test": "first"}]}'
        second_json_output = '{"SPAirPortDataType": [{"test": "second"}]}'

        expect(command_runner).to receive(:call).with(
          described_class::SYSTEM_PROFILER_AIRPORT_ARGS,
          raise_on_error:  true,
          timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
        ).twice.and_return(
          command_result(stdout: first_json_output),
          command_result(stdout: second_json_output)
        )

        provider.with_cache_scope do
          expect(provider.data).to eq({ 'SPAirPortDataType' => [{ 'test' => 'first' }] })

          Thread.new { provider.invalidate_cache }.join

          expect(provider.data).to eq({ 'SPAirPortDataType' => [{ 'test' => 'second' }] })
        end
      end
    end
  end
end
