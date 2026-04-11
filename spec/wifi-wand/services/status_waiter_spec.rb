# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/status_waiter'
require_relative '../../../lib/wifi-wand/timing_constants'

describe WifiWand::StatusWaiter do
  let(:mock_model) do
    double('Model',
      wifi_on?:                    false,
      associated?:                 false,
      internet_connectivity_state: :unreachable,
    )
  end

  let(:waiter) { described_class.new(mock_model, verbose: false) }

  describe '#wait_for' do
    # For each wait state, declare: which model predicate it polls, and what
    # return value from that predicate satisfies the condition.
    state_predicates = {
      wifi_on:       [:wifi_on?,               true],
      wifi_off:      [:wifi_on?,               false],
      associated:    [:associated?,            true],
      disassociated: [:associated?,            false],
      internet_on:   %i[internet_connectivity_state reachable],
      internet_off:  %i[internet_connectivity_state unreachable],
    }.freeze

    state_predicates.each do |state, (predicate, satisfied)|
      context "with :#{state} status" do
        it 'returns nil immediately when already in target state' do
          allow(mock_model).to receive(predicate).and_return(satisfied)

          expect(waiter).not_to receive(:sleep)
          expect(waiter.wait_for(state)).to be_nil
        end

        it 'polls until target state is reached, then returns nil' do
          call_count = 0
          allow(mock_model).to receive(predicate) do
            # Return the unsatisfied value for the first two calls, then satisfied
            (call_count += 1) > 2 ? satisfied : !satisfied
          end
          allow(waiter).to receive(:sleep)

          expect(waiter.wait_for(state, wait_interval_in_secs: WifiWand::TimingConstants::FAST_TEST_INTERVAL))
            .to be_nil
        end
      end
    end

    context 'with removed legacy state names' do
      # Map each removed name to the pattern and replacement names expected in the hint.
      legacy_hints = {
        conn: { pattern: /:conn.*was removed/i, replacements: %i[internet_on associated] },
        disc: { pattern: /:disc.*was removed/i, replacements: %i[internet_off disassociated] },
        on:   { pattern: /:on.*was removed/i,   replacements: %i[wifi_on] },
        off:  { pattern: /:off.*was removed/i,  replacements: %i[wifi_off] },
      }.freeze

      legacy_hints.each do |legacy_state, config|
        it "raises ArgumentError with actionable migration hint for :#{legacy_state}" do
          expect { waiter.wait_for(legacy_state) }.to raise_error(ArgumentError) do |e|
            expect(e.message).to match(config[:pattern])
            config[:replacements].each { |r| expect(e.message).to include(":#{r}") }
          end
        end
      end

      it 'always includes the full valid-states list in legacy hint messages' do
        expect { waiter.wait_for(:conn) }.to raise_error(ArgumentError, /Valid states:.*wifi_on/)
      end

      it 'legacy hint takes precedence over stringify_permitted_values_in_error_msg flag' do
        expect { waiter.wait_for(:conn, stringify_permitted_values_in_error_msg: true) }
          .to raise_error(ArgumentError, /:conn.*was removed/i)
      end
    end

    context 'with an entirely unknown status' do
      it 'raises ArgumentError listing permitted states' do
        expect { waiter.wait_for(:invalid_status) }
          .to raise_error(ArgumentError, /Option must be one of/)
      end

      it 'stringify_permitted_values_in_error_msg produces a bracketed list' do
        all_states = /Option must be one of \[wifi_on, wifi_off, associated, disassociated,/
        expect { waiter.wait_for(:bogus, stringify_permitted_values_in_error_msg: true) }
          .to raise_error(ArgumentError, all_states)
      end
    end

    context 'with verbose mode enabled' do
      let(:verbose_waiter) { described_class.new(mock_model, verbose: true) }

      before do
        call_count = 0
        allow(mock_model).to receive(:wifi_on?) { (call_count += 1) > 1 }
        allow(verbose_waiter).to receive(:sleep)
      end

      it 'logs start message with timeout and interval' do
        expect do
          verbose_waiter.wait_for(:wifi_on, wait_interval_in_secs: WifiWand::TimingConstants::FAST_TEST_INTERVAL)
        end.to output(
          /StatusWaiter \(wifi_on\): starting, timeout: never, interval: #{WifiWand::TimingConstants::FAST_TEST_INTERVAL}s/,
        ).to_stdout
      end

      it 'logs completion message when condition is already met' do
        allow(mock_model).to receive(:wifi_on?).and_return(true)
        expect { verbose_waiter.wait_for(:wifi_on) }
          .to output(/StatusWaiter \(wifi_on\): completed without needing to wait/).to_stdout
      end

      it 'logs total wait time after polling' do
        expect do
          verbose_waiter.wait_for(:wifi_on, wait_interval_in_secs: WifiWand::TimingConstants::FAST_TEST_INTERVAL)
        end.to output(/StatusWaiter \(wifi_on\): wait time \(seconds\):/).to_stdout
      end
    end

    context 'when testing timing behaviour' do
      it 'reports elapsed time accurately via monotonic clock' do
        call_count = 0
        allow(mock_model).to receive(:wifi_on?) { (call_count += 1) > 1 }
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC)
          .and_return(1000.0, 1002.5)

        verbose_waiter = described_class.new(mock_model, verbose: true)
        allow(verbose_waiter).to receive(:sleep)

        expect do
          verbose_waiter.wait_for(:wifi_on, timeout_in_secs: 10)
        end.to output(/StatusWaiter \(wifi_on\): wait time \(seconds\): 2\.5/).to_stdout
      end
    end

    context 'with timeout' do
      it 'raises WaitTimeoutError when timeout elapses before state is reached' do
        expect { waiter.wait_for(:wifi_on, timeout_in_secs: 0) }
          .to raise_error(WifiWand::WaitTimeoutError)
      end
    end

    it 'does not treat an indeterminate internet result as :internet_on' do
      allow(mock_model).to receive(:internet_connectivity_state).and_return(:indeterminate)
      allow(waiter).to receive(:sleep)

      expect do
        waiter.wait_for(:internet_on, timeout_in_secs: 0, wait_interval_in_secs: 0)
      end.to raise_error(WifiWand::WaitTimeoutError)
    end

    it 'does not treat an indeterminate internet result as :internet_off' do
      allow(mock_model).to receive(:internet_connectivity_state).and_return(:indeterminate)
      allow(waiter).to receive(:sleep)

      expect do
        waiter.wait_for(:internet_off, timeout_in_secs: 0, wait_interval_in_secs: 0)
      end.to raise_error(WifiWand::WaitTimeoutError)
    end
  end

  describe 'integration with BaseModel' do
    it 'is accessible through BaseModel#till (delegates to wait_for)' do
      require_relative '../../../lib/wifi-wand/models/base_model'
      require 'ostruct'
      model = WifiWand::BaseModel.new(OpenStruct.new(verbose: false))
      allow(model).to receive(:wifi_on?).and_return(true)
      expect(model.till(:wifi_on)).to be_nil
    end
  end
end
