# frozen_string_literal: true

require_relative '../../spec_helper'
require 'rbconfig'
require 'json'
require_relative '../../../lib/wifi_wand/services/network_connectivity_tester'
require_relative '../../../lib/wifi_wand/services/captive_portal_checker'

describe 'Probe Cleanup Regressions' do
  include TestHelpers

  let(:ruby_bin) { RbConfig.ruby }
  let(:spawned_pids) { [] }
  # JRuby helper startup is significantly slower than CRuby, so allow more
  # time for the spawned helper to write its result before the parent times out.
  let(:probe_helper_timeout) { RUBY_PLATFORM == 'java' ? 10 : 1 }

  after do
    spawned_pids.each { |pid| kill_and_reap_process(pid) }
  end

  def sleeping_helper_script(payload, delay)
    # Pre-serialize the payload so the spawned helper does not need to load
    # JSON itself. This keeps JRuby helper startup fast enough to write its
    # result before the parent-side timeout fires.
    payload_json = payload.to_json
    <<~RUBY
      STDOUT.write(#{payload_json.inspect})
      STDOUT.flush
      sleep(#{delay})
    RUBY
  end

  describe 'NetworkConnectivityTester' do
    let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

    it 'reaps a successful TCP helper that keeps running after writing valid JSON' do
      payload = { success: true, timed_out: false, probe_results: [] }
      helper_pid = nil

      allow(tester).to receive(:start_connectivity_probe) do |_items, _mode, _timeout|
        reader, writer = IO.pipe
        pid = Process.spawn(ruby_bin, '-e', sleeping_helper_script(payload, 5), out: writer, err: File::NULL)
        writer.close
        spawned_pids << pid
        helper_pid = pid
        { pid: pid, reader: reader, helper_mode: :tcp, buffer: +'', eof: false }
      end

      result = tester.tcp_connectivity?(overall_timeout: probe_helper_timeout)
      expect(result).to be true

      # Verify helper is reaped
      expect(helper_pid).not_to be_nil
      expect_process_dead(helper_pid)
    end

    it 'reaps a successful DNS helper that keeps running after writing valid JSON' do
      payload = { success: true, timed_out: false, probe_results: [] }
      helper_pid = nil

      allow(tester).to receive(:start_connectivity_probe) do |_items, _mode, _timeout|
        reader, writer = IO.pipe
        pid = Process.spawn(ruby_bin, '-e', sleeping_helper_script(payload, 5), out: writer, err: File::NULL)
        writer.close
        spawned_pids << pid
        helper_pid = pid
        { pid: pid, reader: reader, helper_mode: :dns, buffer: +'', eof: false }
      end

      result = tester.dns_working?(overall_timeout: probe_helper_timeout)
      expect(result).to be true

      # Verify helper is reaped
      expect(helper_pid).not_to be_nil
      expect_process_dead(helper_pid)
    end
  end

  describe 'CaptivePortalChecker' do
    let(:checker) { WifiWand::CaptivePortalChecker.new(verbose: false) }
    let(:endpoint) { { url: 'http://example.com', expected_code: 204 } }

    before do
      allow(checker).to receive(:captive_portal_check_endpoints).and_return([endpoint])
    end

    it 'reaps a successful captive portal helper that keeps running after writing valid JSON' do
      payload = { login_required: 'no', actual_code: 204 }
      helper_pid = nil

      allow(checker).to receive(:start_captive_portal_probe) do |_endpoint|
        reader, writer = IO.pipe
        pid = Process.spawn(ruby_bin, '-e', sleeping_helper_script(payload, 5), out: writer, err: File::NULL)
        writer.close
        spawned_pids << pid
        helper_pid = pid
        { pid: pid, reader: reader, endpoint: endpoint, buffer: +'', eof: false }
      end

      result = checker.captive_portal_login_required(timeout_in_secs: probe_helper_timeout)
      expect(result).to eq(:no)

      # Verify helper is reaped
      expect(helper_pid).not_to be_nil
      expect_process_dead(helper_pid)
    end
  end
end
