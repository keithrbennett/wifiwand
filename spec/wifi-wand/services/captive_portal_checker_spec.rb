# frozen_string_literal: true

require_relative '../../spec_helper'
require 'stringio'
require_relative '../../../lib/wifi-wand/services/captive_portal_checker'

describe WifiWand::CaptivePortalChecker do
  include TestHelpers

  describe '#captive_portal_free?' do
    let(:checker) { described_class.new(verbose: false) }

    context 'when the connectivity check endpoint returns 204' do
      before { mock_captive_portal_free }

      it 'returns true' do
        expect(checker.captive_portal_free?).to be true
      end
    end

    context 'when the connectivity check endpoint returns a redirect (captive portal)' do
      before { mock_captive_portal_detected }

      it 'returns false' do
        expect(checker.captive_portal_free?).to be false
      end
    end

    context 'when all HTTP requests fail with network errors' do
      before do
        stub_short_connectivity_timeouts
        allow(Net::HTTP).to receive(:get_response).and_raise(Errno::ECONNREFUSED)
      end

      it 'returns true (assumes free to avoid false negatives)' do
        expect(checker.captive_portal_free?).to be true
      end
    end

    context 'with verbose mode' do
      let(:output) { StringIO.new }
      let(:checker) { described_class.new(verbose: true, output: output) }

      before { mock_captive_portal_free }

      it 'logs the endpoints being checked' do
        checker.captive_portal_free?
        expect(output.string).to match(/Testing captive portal via HTTP:/)
      end

      it 'logs a pass result' do
        checker.captive_portal_free?
        expect(output.string).to include('pass')
      end
    end

    context 'with verbose mode and captive portal detected' do
      let(:output) { StringIO.new }
      let(:checker) { described_class.new(verbose: true, output: output) }

      before { mock_captive_portal_detected }

      it 'logs results array and detected status' do
        checker.captive_portal_free?
        expect(output.string).to include('mismatch')
        expect(output.string).to include('detected')
      end
    end

    context 'with multiple endpoints (redundancy)' do
      let(:checker) { described_class.new(verbose: false) }
      let(:endpoints) do
        [
          { url: 'http://first.example.com/check', expected_code: 204 },
          { url: 'http://second.example.com/check', expected_code: 204 },
        ]
      end

      before do
        allow(checker).to receive(:captive_portal_check_endpoints).and_return(endpoints)
      end

      it 'returns true when first endpoint returns wrong status but second returns 204' do
        allow(checker).to receive(:attempt_captive_portal_check).and_return(false, true)
        expect(checker.captive_portal_free?).to be true
      end

      it 'returns true when first endpoint has network error and second returns 204' do
        allow(checker).to receive(:attempt_captive_portal_check).and_return(nil, true)
        expect(checker.captive_portal_free?).to be true
      end

      it 'returns false when all endpoints return wrong status' do
        allow(checker).to receive(:attempt_captive_portal_check).and_return(false, false)
        expect(checker.captive_portal_free?).to be false
      end

      it 'returns true when all endpoints have network errors' do
        allow(checker).to receive(:attempt_captive_portal_check).and_return(nil, nil)
        expect(checker.captive_portal_free?).to be true
      end
    end
  end
end
