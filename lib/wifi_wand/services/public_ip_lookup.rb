# frozen_string_literal: true

require 'ipaddr'
require 'json'
require 'net/http'
require 'openssl'
require 'uri'

require_relative '../errors'

module WifiWand
  class PublicIpLookup
    PUBLIC_IP_TIMEOUT_IN_SECONDS = 3
    PUBLIC_IP_MAX_ATTEMPTS = 3
    PUBLIC_IP_RETRY_BASE_DELAY_IN_SECONDS = 0.2
    COUNTRY_CODE_REGEX = /\A[A-Z]{2}\z/

    def info
      uri = URI.parse('https://api.country.is/')
      response = public_ip_http_get(uri)
      parsed = JSON.parse(response.body)

      address = parsed['ip'].to_s.strip
      country = parsed['country'].to_s.strip.upcase

      unless valid_public_ip_address?(address) && country.match?(COUNTRY_CODE_REGEX)
        raise(PublicIPLookupError.new(
          status_code:    nil,
          status_message: nil,
          message:        'Public IP lookup failed: malformed response',
          url:            uri.to_s,
          body:           response.body
        ))
      end

      { 'address' => address, 'country' => country }
    rescue JSON::ParserError
      raise(PublicIPLookupError.new(
        status_code:    nil,
        status_message: nil,
        message:        'Public IP lookup failed: malformed response',
        url:            uri.to_s,
        body:           response&.body
      ))
    end

    def address
      uri = URI.parse('https://api.ipify.org')
      response = public_ip_http_get(uri)
      address = response.body.to_s.strip

      if valid_public_ip_address?(address)
        address
      else
        raise(PublicIPLookupError.new(
          status_code:    nil,
          status_message: nil,
          message:        'Public IP lookup failed: malformed response',
          url:            uri.to_s,
          body:           response.body
        ))
      end
    end

    def country = info.fetch('country')

    private def valid_public_ip_address?(address)
      IPAddr.new(address)
      true
    rescue IPAddr::InvalidAddressError
      false
    end

    private def public_ip_http_get(uri)
      attempts = 0

      begin
        attempts += 1
        public_ip_http_get_once(uri)
      rescue PublicIPLookupError => e
        raise unless public_ip_retryable_error?(e)
        raise if attempts >= PUBLIC_IP_MAX_ATTEMPTS

        sleep(public_ip_retry_delay(attempts))
        retry
      end
    end

    private def public_ip_http_get_once(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = PUBLIC_IP_TIMEOUT_IN_SECONDS
      http.read_timeout = PUBLIC_IP_TIMEOUT_IN_SECONDS
      http.write_timeout = PUBLIC_IP_TIMEOUT_IN_SECONDS if http.respond_to?(:write_timeout=)

      response = http.request(Net::HTTP::Get.new(uri.request_uri))
      return response if response.is_a?(Net::HTTPSuccess)

      if response.code == '429'
        raise(PublicIPLookupError.new(
          status_code:    response.code,
          status_message: response.message,
          message:        'Public IP lookup failed: rate limited',
          url:            uri.to_s
        ))
      end

      raise(PublicIPLookupError.new(
        status_code:    response.code,
        status_message: response.message,
        message:        "Public IP lookup failed: HTTP #{response.code} #{response.message}",
        url:            uri.to_s
      ))
    rescue Timeout::Error, Errno::ETIMEDOUT
      raise(PublicIPLookupError.new(
        status_code:    nil,
        status_message: nil,
        message:        'Public IP lookup failed: timeout',
        url:            uri.to_s
      ))
    rescue SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError
      raise(PublicIPLookupError.new(
        status_code:    nil,
        status_message: nil,
        message:        'Public IP lookup failed: network error',
        url:            uri.to_s
      ))
    end

    private def public_ip_retry_delay(attempts_completed)
      PUBLIC_IP_RETRY_BASE_DELAY_IN_SECONDS * (2**(attempts_completed - 1))
    end

    private def public_ip_retryable_error?(error)
      return true if error.status_code.nil?

      error.status_code.to_i >= 500
    end
  end
end
