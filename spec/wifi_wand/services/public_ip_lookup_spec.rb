# frozen_string_literal: true

require_relative '../../spec_helper'

describe WifiWand::PublicIpLookup do
  subject(:lookup) { described_class.new }

  let(:fake_http) { double('http') }

  before do
    allow(fake_http).to receive(:use_ssl=)
    allow(fake_http).to receive(:open_timeout=)
    allow(fake_http).to receive(:read_timeout=)
    allow(fake_http).to receive(:respond_to?).with(:write_timeout=).and_return(false)
    allow(Net::HTTP).to receive(:new).and_return(fake_http)
  end

  describe '#info' do
    it 'parses successful info responses' do
      fake_response = double('response', body: '{"ip":"203.0.113.5","country":"TH"}')
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(fake_http).to receive(:request).and_return(fake_response)

      expect(lookup.info).to eq('address' => '203.0.113.5', 'country' => 'TH')
    end

    it 'parses successful IPv6 info responses' do
      fake_response = double('response', body: '{"ip":"2001:db8::1","country":"TH"}')
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(fake_http).to receive(:request).and_return(fake_response)

      expect(lookup.info).to eq('address' => '2001:db8::1', 'country' => 'TH')
    end

    it 'stores malformed response details on the error' do
      fake_response = double('response', body: '{"ip":"not-an-ip","country":"TH"}')
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(fake_http).to receive(:request).and_return(fake_response)

      expect { lookup.info }.to raise_error(WifiWand::PublicIPLookupError) { |error|
        expect(error.message).to eq('Public IP lookup failed: malformed response')
        expect(error.url).to eq('https://api.country.is/')
        expect(error.body).to eq('{"ip":"not-an-ip","country":"TH"}')
      }
    end

    it 'raises rate limit errors clearly' do
      fake_response = instance_double(Net::HTTPResponse, code: '429', message: 'Too Many Requests')
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(fake_http).to receive(:request).and_return(fake_response)
      allow(lookup).to receive(:sleep)

      expect { lookup.info }
        .to raise_error(WifiWand::PublicIPLookupError, 'Public IP lookup failed: rate limited') { |error|
          expect(error.status_code).to eq('429')
        }
      expect(fake_http).to have_received(:request).once
      expect(lookup).not_to have_received(:sleep)
    end
  end

  describe '#address' do
    it 'parses successful address responses' do
      fake_response = double('response', body: '203.0.113.5')
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(fake_http).to receive(:request).and_return(fake_response)

      expect(lookup.address).to eq('203.0.113.5')
    end

    it 'raises timeout errors clearly' do
      allow(lookup).to receive(:sleep)
      allow(fake_http).to receive(:request).and_raise(Net::ReadTimeout)

      expect { lookup.address }
        .to raise_error(WifiWand::PublicIPLookupError, 'Public IP lookup failed: timeout')
    end

    it 'retries transient timeout errors before returning a successful address' do
      allow(lookup).to receive(:sleep)
      fake_response = double('response', body: '203.0.113.5')
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      request_count = 0
      allow(fake_http).to receive(:request) do
        request_count += 1
        raise Net::ReadTimeout if request_count < 3

        fake_response
      end

      expect(lookup.address).to eq('203.0.113.5')
      expect(lookup).to have_received(:sleep).with(0.2)
      expect(lookup).to have_received(:sleep).with(0.4)
    end

    it 'stops after the configured retry budget is exhausted' do
      allow(lookup).to receive(:sleep)
      allow(fake_http).to receive(:request).and_raise(SocketError, 'lookup failed')

      expect { lookup.address }
        .to raise_error(WifiWand::PublicIPLookupError, 'Public IP lookup failed: network error')
      expect(fake_http).to have_received(:request).exactly(3).times
    end

    it 'does not retry non-rate-limited client errors' do
      fake_response = instance_double(Net::HTTPResponse, code: '400', message: 'Bad Request')
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(fake_http).to receive(:request).and_return(fake_response)
      allow(lookup).to receive(:sleep)

      expect { lookup.address }
        .to raise_error(WifiWand::PublicIPLookupError, 'Public IP lookup failed: HTTP 400 Bad Request')
      expect(fake_http).to have_received(:request).once
      expect(lookup).not_to have_received(:sleep)
    end

    it 'preserves the request URL on transport errors' do
      allow(lookup).to receive(:sleep)
      allow(fake_http).to receive(:request).and_raise(SocketError, 'lookup failed')

      expect { lookup.address }.to raise_error(WifiWand::PublicIPLookupError) { |error|
        expect(error.message).to eq('Public IP lookup failed: network error')
        expect(error.url).to eq('https://api.ipify.org')
      }
    end

    it 'raises transport errors clearly' do
      allow(lookup).to receive(:sleep)
      allow(fake_http).to receive(:request).and_raise(SocketError, 'lookup failed')

      expect { lookup.address }
        .to raise_error(WifiWand::PublicIPLookupError, 'Public IP lookup failed: network error')
    end

    it 'raises PublicIPLookupError when response is not success' do
      response = instance_double(Net::HTTPResponse, code: '500', message: 'Internal Server Error')
      allow(response).to receive(:is_a?).and_return(false)

      http = instance_double(Net::HTTP)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:respond_to?).with(:write_timeout=).and_return(true)
      allow(http).to receive(:write_timeout=)
      allow(http).to receive(:request).and_return(response)
      allow(Net::HTTP).to receive(:new).and_return(http)

      expect { lookup.address }
        .to raise_error(WifiWand::PublicIPLookupError,
          'Public IP lookup failed: HTTP 500 Internal Server Error')
    end

    it 'retries server errors before returning a successful address' do
      allow(lookup).to receive(:sleep)
      server_error = double('server_error', code: '503', message: 'Service Unavailable')
      allow(server_error).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      success = double('response', body: '203.0.113.5')
      allow(success).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      request_count = 0
      allow(fake_http).to receive(:request) do
        request_count += 1
        if request_count < 3
          server_error
        else
          success
        end
      end

      expect(lookup.address).to eq('203.0.113.5')
      expect(lookup).to have_received(:sleep).with(0.2)
      expect(lookup).to have_received(:sleep).with(0.4)
    end
  end

  describe '#country' do
    it 'returns the country from info' do
      fake_response = double('response', body: '{"ip":"203.0.113.5","country":"TH"}')
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(fake_http).to receive(:request).and_return(fake_response)

      expect(lookup.country).to eq('TH')
    end
  end
end
