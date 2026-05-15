# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/platforms/mac/connected_network_flag_context'

module WifiWand
  describe Platforms::Mac::ConnectedNetworkFlagContext do
    subject(:harness) { harness_class.new }

    let(:harness_class) do
      Class.new do
        include Platforms::Mac::ConnectedNetworkFlagContext

        def with_scope(&block)
          send(:with_connected_network_flag_scope, &block)
        end

        def mark_disconnected
          send(:mark_connected_network_authoritatively_disconnected)
        end

        def disconnected?
          send(:connected_network_authoritatively_disconnected?)
        end

        def mark_redacted
          send(:mark_connected_network_fallback_identity_redacted)
        end

        def redacted?
          send(:connected_network_fallback_identity_redacted?)
        end

        def contexts
          send(:current_connected_network_flag_contexts)
        end
      end
    end

    after do
      Thread.current[described_class::FLAG_CONTEXTS_KEY] = nil
    end

    it 'leaves flags false when no connected-network scope is active' do
      expect(harness.mark_disconnected).to be_nil
      expect(harness.mark_redacted).to be_nil

      expect(harness.disconnected?).to be(false)
      expect(harness.redacted?).to be(false)
      expect(harness.contexts).to be_nil
    end

    it 'propagates marked flags within the active connected-network scope' do
      observed = nil

      harness.with_scope do
        observed = [
          harness.disconnected?,
          harness.mark_disconnected,
          harness.disconnected?,
          harness.redacted?,
          harness.mark_redacted,
          harness.redacted?,
        ]
      end

      expect(observed).to eq([false, nil, true, false, nil, true])
      expect(harness.contexts).to be_nil
    end

    it 'restores an outer scope after a nested connected-network scope exits' do
      snapshots = {}

      harness.with_scope do
        harness.mark_redacted
        snapshots[:outer_before] = [harness.disconnected?, harness.redacted?]

        harness.with_scope do
          snapshots[:inner_initial] = [harness.disconnected?, harness.redacted?]
          harness.mark_disconnected
          snapshots[:inner_after_mark] = [harness.disconnected?, harness.redacted?]
        end

        snapshots[:outer_after] = [harness.disconnected?, harness.redacted?]
      end

      expect(snapshots).to eq(
        outer_before:     [false, true],
        inner_initial:    [false, false],
        inner_after_mark: [true, false],
        outer_after:      [false, true]
      )
      expect(harness.contexts).to be_nil
    end

    it 'keeps connected-network scopes thread-local' do
      thread_result = Queue.new
      snapshots = {}

      harness.with_scope do
        harness.mark_redacted

        thread = Thread.new do
          thread_result << [harness.disconnected?, harness.redacted?]
          harness.with_scope do
            harness.mark_disconnected
            thread_result << [harness.disconnected?, harness.redacted?]
          end
          thread_result << harness.contexts
        end
        thread.join

        snapshots[:thread_initial] = thread_result.pop
        snapshots[:thread_inner] = thread_result.pop
        snapshots[:thread_contexts_after] = thread_result.pop
        snapshots[:outer_after_thread] = [harness.disconnected?, harness.redacted?]
      end

      expect(snapshots).to eq(
        thread_initial:        [false, false],
        thread_inner:          [true, false],
        thread_contexts_after: nil,
        outer_after_thread:    [false, true]
      )
      expect(harness.contexts).to be_nil
    end

    it 'restores the previous scope when a nested connected-network scope raises' do
      snapshots = {}

      harness.with_scope do
        harness.mark_redacted

        begin
          harness.with_scope do
            harness.mark_disconnected
            raise 'inner scope failed'
          end
        rescue RuntimeError => e
          snapshots[:error_message] = e.message
        end

        snapshots[:outer_after_exception] = [harness.disconnected?, harness.redacted?]
      end

      expect(snapshots).to eq(
        error_message:         'inner scope failed',
        outer_after_exception: [false, true]
      )
      expect(harness.contexts).to be_nil
    end

    it 'clears the active context when an outer connected-network scope raises' do
      expect do
        harness.with_scope do
          harness.mark_disconnected
          raise 'outer scope failed'
        end
      end.to raise_error(RuntimeError, 'outer scope failed')

      expect(harness.disconnected?).to be(false)
      expect(harness.redacted?).to be(false)
      expect(harness.contexts).to be_nil
    end
  end
end
