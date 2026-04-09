# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/status_waiter'
require_relative '../../../lib/wifi-wand/timing_constants'

describe WifiWand::StatusWaiter do
  let(:mock_model) do
    double('Model',
      wifi_on?:               false,
      associated?:            false,
      connected_to_internet?: false,
    )
  end

  let(:waiter) { described_class.new(mock_model, verbose: false) }

  describe '#wait_for' do
    context 'with :wifi_on status' do
      it 'returns immediately when wifi is already on' do
        allow(mock_model).to receive(:wifi_on?).and_return(true)

        expect(waiter).not_to receive(:sleep)
        expect(waiter.wait_for(:wifi_on)).to be_nil
      end

      it 'waits until wifi turns on' do
        call_count = 0
        allow(mock_model).to receive(:wifi_on?) do
          call_count += 1
          call_count > 2
        end
        allow(waiter).to receive(:sleep)
        expect(waiter.wait_for(:wifi_on)).to be_nil
      end
    end

    context 'with :wifi_off status' do
      it 'returns immediately when wifi is already off' do
        allow(mock_model).to receive(:wifi_on?).and_return(false)

        expect(waiter).not_to receive(:sleep)
        expect(waiter.wait_for(:wifi_off)).to be_nil
      end

      it 'waits until wifi turns off' do
        call_count = 0
        allow(mock_model).to receive(:wifi_on?) do
          call_count += 1
          call_count <= 2
        end
        allow(waiter).to receive(:sleep)
        expect(waiter.wait_for(:wifi_off, wait_interval_in_secs: WifiWand::TimingConstants::FAST_TEST_INTERVAL))
          .to be_nil
      end
    end

    context 'with :associated status' do
      it 'returns immediately when already associated' do
        allow(mock_model).to receive(:associated?).and_return(true)

        expect(waiter).not_to receive(:sleep)
        expect(waiter.wait_for(:associated)).to be_nil
      end

      it 'waits until associated' do
        call_count = 0
        allow(mock_model).to receive(:associated?) do
          call_count += 1
          call_count > 2
        end
        allow(waiter).to receive(:sleep)
        expect(waiter.wait_for(:associated, wait_interval_in_secs: WifiWand::TimingConstants::FAST_TEST_INTERVAL))
          .to be_nil
      end
    end

    context 'with :disassociated status' do
      it 'returns immediately when already disassociated' do
        allow(mock_model).to receive(:associated?).and_return(false)

        expect(waiter).not_to receive(:sleep)
        expect(waiter.wait_for(:disassociated)).to be_nil
      end

      it 'waits until disassociated' do
        call_count = 0
        allow(mock_model).to receive(:associated?) do
          call_count += 1
          call_count <= 2
        end
        allow(waiter).to receive(:sleep)
        expect(waiter.wait_for(:disassociated, wait_interval_in_secs: WifiWand::TimingConstants::FAST_TEST_INTERVAL))
          .to be_nil
      end
    end

    context 'with :internet_on status' do
      it 'returns immediately when already connected to internet' do
        allow(mock_model).to receive(:connected_to_internet?).and_return(true)

        expect(waiter).not_to receive(:sleep)
        expect(waiter.wait_for(:internet_on)).to be_nil
      end

      it 'waits until connected to internet' do
        call_count = 0
        allow(mock_model).to receive(:connected_to_internet?) do
          call_count += 1
          call_count > 2
        end
        allow(waiter).to receive(:sleep)
        expect(waiter.wait_for(:internet_on, wait_interval_in_secs: WifiWand::TimingConstants::FAST_TEST_INTERVAL))
          .to be_nil
      end
    end

    context 'with :internet_off status' do
      it 'returns immediately when already disconnected from internet' do
        allow(mock_model).to receive(:connected_to_internet?).and_return(false)

        expect(waiter).not_to receive(:sleep)
        expect(waiter.wait_for(:internet_off)).to be_nil
      end

      it 'waits until disconnected from internet' do
        call_count = 0
        allow(mock_model).to receive(:connected_to_internet?) do
          call_count += 1
          call_count <= 2
        end
        allow(waiter).to receive(:sleep)
        expect(waiter.wait_for(:internet_off, wait_interval_in_secs: WifiWand::TimingConstants::FAST_TEST_INTERVAL))
          .to be_nil
      end
    end

    context 'with removed legacy state names' do
      %i[conn disc on off].each do |legacy_state|
        it "raises ArgumentError for removed state :#{legacy_state}" do
          expect do
            waiter.wait_for(legacy_state)
          end.to raise_error(ArgumentError, /Option must be one of/)
        end
      end
    end

    context 'with invalid status' do
      it 'raises ArgumentError for unknown status' do
        expect do
          waiter.wait_for(:invalid_status)
        end.to raise_error(ArgumentError, /Option must be one of/)
      end

      it 'can stringify permitted values in error message' do
        expect do
          waiter.wait_for(:bogus, stringify_permitted_values_in_error_msg: true)
        end.to raise_error(
          ArgumentError,
          /Option must be one of \[wifi_on, wifi_off, associated, disassociated, internet_on, internet_off\]/
        )
      end

      it 'error message for legacy :conn names the replacement options' do
        expect do
          waiter.wait_for(:conn, stringify_permitted_values_in_error_msg: true)
        end.to raise_error(ArgumentError, /internet_on.*associated|associated.*internet_on/i)
      end
    end

    context 'with verbose mode enabled' do
      let(:verbose_waiter) { described_class.new(mock_model, verbose: true) }

      it 'logs waiting information when condition is not met initially' do
        call_count = 0
        allow(mock_model).to receive(:wifi_on?) do
          call_count += 1
          call_count > 1
        end

        allow(verbose_waiter).to receive(:sleep)

        expect do
          verbose_waiter.wait_for(:wifi_on, wait_interval_in_secs: WifiWand::TimingConstants::FAST_TEST_INTERVAL)
        end.to output(
          /StatusWaiter \(wifi_on\): starting, timeout: never, interval: #{WifiWand::TimingConstants::FAST_TEST_INTERVAL}s/
        ).to_stdout
      end

      it 'logs completion message when condition is already met' do
        allow(mock_model).to receive(:wifi_on?).and_return(true)
        expect do
          verbose_waiter.wait_for(:wifi_on)
        end.to output(/StatusWaiter \(wifi_on\): completed without needing to wait/).to_stdout
      end

      it 'logs total wait time when waiting is required' do
        call_count = 0
        allow(mock_model).to receive(:wifi_on?) do
          call_count += 1
          call_count > 1
        end

        allow(verbose_waiter).to receive(:sleep)

        expect do
          verbose_waiter.wait_for(:wifi_on, wait_interval_in_secs: WifiWand::TimingConstants::FAST_TEST_INTERVAL)
        end.to output(/StatusWaiter \(wifi_on\): wait time \(seconds\):/).to_stdout
      end
    end

    context 'when testing timing behavior' do
      it 'measures wait time accurately' do
        call_count = 0
        allow(mock_model).to receive(:wifi_on?) do
          call_count += 1
          call_count > 1
        end

        start_time = 1000.0
        end_time = 1002.5
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC)
          .and_return(start_time, end_time)

        verbose_waiter = described_class.new(mock_model, verbose: true)
        allow(verbose_waiter).to receive(:sleep)

        expect do
          verbose_waiter.wait_for(:wifi_on, timeout_in_secs: 10)
        end.to output(/StatusWaiter \(wifi_on\): wait time \(seconds\): 2\.5/).to_stdout
      end
    end

    context 'with timeout' do
      it 'raises WaitTimeoutError when timeout elapses' do
        allow(mock_model).to receive_messages(wifi_on?: false, associated?: false, connected_to_internet?: false)

        expect do
          waiter.wait_for(:wifi_on, timeout_in_secs: 0)
        end.to raise_error(WifiWand::WaitTimeoutError)
      end
    end
  end

  describe 'integration with BaseModel' do
    it 'is accessible through BaseModel till method (delegates to wait_for)' do
      require_relative '../../../lib/wifi-wand/models/base_model'
      require 'ostruct'
      model = WifiWand::BaseModel.new(OpenStruct.new(verbose: false))
      allow(model).to receive(:wifi_on?).and_return(true)
      expect(model.till(:wifi_on)).to be_nil
    end
  end
end
