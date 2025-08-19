require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/status_waiter'
require_relative '../../../lib/wifi-wand/timing_constants'

describe WifiWand::StatusWaiter do
  let(:mock_model) do
    double('Model',
      wifi_on?: false,
      connected_to_internet?: false
    )
  end

  let(:waiter) { WifiWand::StatusWaiter.new(mock_model, verbose: false) }

  describe '#wait_for' do
    context 'with :on status' do
      it 'returns immediately when wifi is already on' do
        allow(mock_model).to receive(:wifi_on?).and_return(true)
        
        # Verify sleep is never called
        expect(waiter).not_to receive(:sleep)
        
        expect(waiter.wait_for(:on)).to be_nil
      end

      it 'waits until wifi turns on' do
        call_count = 0
        allow(mock_model).to receive(:wifi_on?) do
          call_count += 1
          call_count > 2  # Simulate wifi turning on after 2 checks
        end
        allow(waiter).to receive(:sleep)  # Mock sleep to speed up test
        expect(waiter.wait_for(:on)).to be_nil  # No timeout needed because `sleep` is mocked
      end
    end

    context 'with :off status' do
      it 'returns immediately when wifi is already off' do
        allow(mock_model).to receive(:wifi_on?).and_return(false)
        
        # Verify sleep is never called
        expect(waiter).not_to receive(:sleep)
        
        expect(waiter.wait_for(:off)).to be_nil
      end

      it 'waits until wifi turns off' do
        call_count = 0
        allow(mock_model).to receive(:wifi_on?) do
          call_count += 1
          call_count <= 2  # Simulate wifi turning off after 2 checks
        end
        allow(waiter).to receive(:sleep)  # Mock sleep to speed up test
        expect(waiter.wait_for(:off, WifiWand::TimingConstants::FAST_TEST_INTERVAL)).to be_nil
      end
    end

    context 'with :conn status' do
      it 'returns immediately when already connected to internet' do
        allow(mock_model).to receive(:connected_to_internet?).and_return(true)
        
        # Verify sleep is never called
        expect(waiter).not_to receive(:sleep)
        
        expect(waiter.wait_for(:conn)).to be_nil
      end

      it 'waits until connected to internet' do
        call_count = 0
        allow(mock_model).to receive(:connected_to_internet?) do
          call_count += 1
          call_count > 2  # Simulate connection after 2 checks
        end
        allow(waiter).to receive(:sleep)  # Mock sleep to speed up test
        expect(waiter.wait_for(:conn, WifiWand::TimingConstants::FAST_TEST_INTERVAL)).to be_nil
      end
    end

    context 'with :disc status' do
      it 'returns immediately when already disconnected from internet' do
        allow(mock_model).to receive(:connected_to_internet?).and_return(false)
        
        # Verify sleep is never called
        expect(waiter).not_to receive(:sleep)
        
        expect(waiter.wait_for(:disc)).to be_nil
      end

      it 'waits until disconnected from internet' do
        call_count = 0
        allow(mock_model).to receive(:connected_to_internet?) do
          call_count += 1
          call_count <= 2  # Simulate disconnection after 2 checks
        end
        allow(waiter).to receive(:sleep)  # Mock sleep to speed up test
        expect(waiter.wait_for(:disc, WifiWand::TimingConstants::FAST_TEST_INTERVAL)).to be_nil
      end
    end

    context 'with invalid status' do
      it 'raises ArgumentError for unknown status' do
        expect {
          waiter.wait_for(:invalid_status)
        }.to raise_error(ArgumentError, /Option must be one of/)
      end
    end


    context 'with verbose mode enabled' do
      let(:verbose_waiter) { WifiWand::StatusWaiter.new(mock_model, verbose: true) }

      it 'logs waiting information when condition is not met initially' do
        call_count = 0
        allow(mock_model).to receive(:wifi_on?) do
          call_count += 1
          call_count > 1  # Will need to wait
        end
        
        allow(verbose_waiter).to receive(:sleep)  # Mock sleep
        
        expect {
          verbose_waiter.wait_for(:on, WifiWand::TimingConstants::FAST_TEST_INTERVAL)
        }.to output(/StatusWaiter: waiting for on, interval.*#{WifiWand::TimingConstants::FAST_TEST_INTERVAL}/).to_stdout
      end

      it 'logs completion message when condition is already met' do
        allow(mock_model).to receive(:wifi_on?).and_return(true)
        expect {
          verbose_waiter.wait_for(:on)
        }.to output(/StatusWaiter: completed without needing to wait/).to_stdout
      end

      it 'logs total wait time when waiting is required' do
        call_count = 0
        allow(mock_model).to receive(:wifi_on?) do
          call_count += 1
          call_count > 1
        end
        
        allow(verbose_waiter).to receive(:sleep)
        
        expect {
          verbose_waiter.wait_for(:on, WifiWand::TimingConstants::FAST_TEST_INTERVAL)
        }.to output(/StatusWaiter: on wait time \(seconds\):/).to_stdout
      end
    end

    context 'timing behavior' do
      it 'measures wait time accurately' do
        call_count = 0
        allow(mock_model).to receive(:wifi_on?) do
          call_count += 1
          call_count > 1
        end
        
        # Mock the monotonic clock for predictable timing
        start_time = 1000.0
        end_time = 1002.5
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC)
                                                .and_return(start_time, end_time)
        allow(waiter).to receive(:sleep)
        
        verbose_waiter = WifiWand::StatusWaiter.new(mock_model, verbose: true)
        
        expect {
          verbose_waiter.wait_for(:on, WifiWand::TimingConstants::FAST_TEST_INTERVAL)
        }.to output(/StatusWaiter: on wait time \(seconds\): 2\.5/).to_stdout
      end
    end
  end

  describe 'integration with BaseModel' do
    it 'is accessible through BaseModel till method (delegates to wait_for)' do
      require_relative '../../../lib/wifi-wand/models/base_model'
      require 'ostruct'
      model = WifiWand::BaseModel.new(OpenStruct.new(verbose: false))
      allow(model).to receive(:wifi_on?).and_return(true)
      # Test that BaseModel#till delegates to StatusWaiter#wait_for
      expect(model.till(:on)).to be_nil
    end
  end
end