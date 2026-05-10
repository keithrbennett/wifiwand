# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/services/process_probe_manager'

describe WifiWand::ProcessProbeManager do
  let(:manager_class) do
    Class.new do
      include WifiWand::ProcessProbeManager

      const_set(:HELPER_RESULT_GRACE, 0.05)
    end
  end
  let(:manager) { manager_class.new }

  describe '#helper_result_grace' do
    it 'raises clearly when the including class does not define helper grace' do
      manager_without_grace = Class.new do
        include WifiWand::ProcessProbeManager
      end.new

      expect { manager_without_grace.helper_result_grace }
        .to raise_error(NotImplementedError, /must define HELPER_RESULT_GRACE/)
    end
  end

  describe '#finalize_probe' do
    let(:reader) { instance_double(IO, closed?: false) }
    let(:probe) { { pid: 1234, reader: reader } }

    before do
      allow(reader).to receive(:close) do
        allow(reader).to receive(:closed?).and_return(true)
      end
    end

    it 'waits briefly before terminating a result-producing probe that is still alive' do
      allow(manager).to receive(:probe_reaped_within_grace?).with(1234, grace: 0.05)
        .and_return(false, true)
      allow(Process).to receive(:kill)

      manager.finalize_probe(probe)

      expect(reader).to have_received(:close)
      expect(Process).to have_received(:kill).with('TERM', 1234)
      expect(Process).not_to have_received(:kill).with('KILL', 1234)
      expect(probe[:pid]).to be_nil
    end

    it 'escalates to KILL and clears the pid when TERM does not stop the probe' do
      allow(manager).to receive(:probe_reaped_within_grace?).with(1234, grace: 0.05).and_return(false)
      allow(manager).to receive(:wait_for_killed_probe_reap).with(1234)
      allow(Process).to receive(:kill)

      manager.finalize_probe(probe)

      expect(Process).to have_received(:kill).with('TERM', 1234)
      expect(Process).to have_received(:kill).with('KILL', 1234)
      expect(probe[:pid]).to be_nil
    end
  end

  describe '#terminate_probe' do
    let(:reader) { instance_double(IO, closed?: false) }
    let(:probe) { { pid: 1234, reader: reader } }

    before do
      allow(reader).to receive(:close) do
        allow(reader).to receive(:closed?).and_return(true)
      end
    end

    it 'sends TERM, waits for exit, and finalizes the probe' do
      allow(Process).to receive(:kill)
      allow(manager).to receive(:wait_for_probe_exit)
      allow(manager).to receive(:reap_probe)

      manager.terminate_probe(probe)

      expect(Process).to have_received(:kill).with('TERM', 1234).ordered
      expect(manager).to have_received(:wait_for_probe_exit).with(1234, grace: 0.05).ordered
      expect(reader).to have_received(:close)
      expect(probe[:pid]).to be_nil
    end

    it 'swallows ESRCH races and still finalizes the probe' do
      allow(Process).to receive(:kill).with('TERM', 1234).and_raise(Errno::ESRCH)
      allow(manager).to receive(:reap_probe)

      expect { manager.terminate_probe(probe) }.not_to raise_error
      expect(reader).to have_received(:close)
      expect(probe[:pid]).to be_nil
    end
  end

  describe '#wait_for_probe_exit' do
    it 'returns after a prompt reap without escalating to KILL' do
      allow(manager).to receive(:reap_probe).with(1234).and_return(1234)
      allow(Process).to receive(:kill)

      manager.wait_for_probe_exit(1234)

      expect(Process).not_to have_received(:kill).with('KILL', 1234)
    end

    it 'escalates to KILL when the probe misses the grace window' do
      monotonic_times = [0.0, 0.01, 0.02, 0.03, 0.04, 0.05]
      allow(Process).to receive(:clock_gettime)
        .with(Process::CLOCK_MONOTONIC)
        .and_return(*monotonic_times)
      allow(manager).to receive(:sleep)
      allow(manager).to receive(:reap_probe).with(1234).and_return(nil)
      allow(Process).to receive(:kill)

      manager.wait_for_probe_exit(1234)

      expect(Process).to have_received(:kill).with('KILL', 1234)
      expect(manager).to have_received(:reap_probe).with(1234).exactly(5).times
    end

    it 'swallows ESRCH when the probe exits before forced termination' do
      monotonic_times = [0.0, 0.05]
      allow(Process).to receive(:clock_gettime)
        .with(Process::CLOCK_MONOTONIC)
        .and_return(*monotonic_times)
      allow(manager).to receive(:reap_probe).with(1234).and_return(nil)
      allow(Process).to receive(:kill).with('KILL', 1234).and_raise(Errno::ESRCH)

      expect { manager.wait_for_probe_exit(1234, grace: 0.01) }.not_to raise_error
    end
  end
end
