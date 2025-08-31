require 'socket'
require 'timeout'
require 'yaml'
require 'ipaddr'
require_relative '../timing_constants'

module WifiWand
  class NetworkConnectivityTester
    
    def initialize(verbose: false, output: $stdout)
      @verbose = verbose
      @output = output
    end

    # Tests both TCP connectivity to internet hosts and DNS resolution.
    # If tcp_working or dns_working parameters are provided, uses them instead of querying the system.
    def connected_to_internet?(tcp_working = nil, dns_working = nil)
      tcp = tcp_working.nil? ? tcp_connectivity? : tcp_working
      dns = dns_working.nil? ? dns_working? : dns_working
      tcp && dns
    end

    # Tests TCP connectivity to internet hosts (not localhost)
    def tcp_connectivity?
      test_endpoints = tcp_test_endpoints
      
      if @verbose
        endpoints_list = test_endpoints.map { |e| "#{e[:host]}:#{e[:port]}" }.join(', ')
        @output.puts "Testing internet TCP connectivity to: #{endpoints_list}"
      end

      # Test all endpoints in parallel, return as soon as any succeeds
      success = false
      mutex = Mutex.new
      threads = []
      
      test_endpoints.each do |endpoint|
        threads << Thread.new do
          begin
            Timeout.timeout(TimingConstants::TCP_CONNECTION_TIMEOUT) do
              Socket.tcp(endpoint[:host], endpoint[:port], connect_timeout: TimingConstants::TCP_CONNECTION_TIMEOUT) do
                mutex.synchronize { success = true }
                @output.puts "Successfully connected to #{endpoint[:host]}:#{endpoint[:port]}" if @verbose
              end
            end
          rescue => e
            @output.puts "Failed to connect to #{endpoint[:host]}:#{endpoint[:port]}: #{e.class}" if @verbose
            # Don't set success on failure
          end
        end
      end
      
      # Wait for first success or overall timeout
      start_time = Time.now
      while !success && (Time.now - start_time) < TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT
        sleep(0.1)
      end
      
      # Clean up threads
      threads.each { |t| t.kill if t.alive? }
      threads.each { |t| t.join rescue nil }
      
      success
    end

    # Tests DNS resolution capability
    def dns_working?
      test_domains = dns_test_domains
      
      if @verbose
        @output.puts "Testing DNS resolution for domains: #{test_domains.join(', ')}"
      end
      
      # Test all domains in parallel, return as soon as any succeeds
      success = false
      mutex = Mutex.new
      threads = []
      
      test_domains.each do |domain|
        threads << Thread.new do
          begin
            Timeout.timeout(TimingConstants::DNS_RESOLUTION_TIMEOUT) do
              IPSocket.getaddress(domain)
              mutex.synchronize { success = true }
              @output.puts "Successfully resolved #{domain}" if @verbose
            end
          rescue => e
            @output.puts "Failed to resolve #{domain}: #{e.class}" if @verbose
            # Don't set success on failure
          end
        end
      end
      
      # Wait for first success or overall timeout
      start_time = Time.now
      while !success && (Time.now - start_time) < TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT
        sleep(0.1)
      end
      
      # Clean up threads
      threads.each { |t| t.kill if t.alive? }
      threads.each { |t| t.join rescue nil }
      
      success
    end

    private

    def tcp_test_endpoints
      @tcp_test_endpoints ||= begin
        yaml_path = File.join(File.dirname(__FILE__), '..', 'data', 'tcp_test_endpoints.yml')
        data = YAML.safe_load_file(yaml_path)
        data['endpoints'].map { |endpoint| endpoint.transform_keys(&:to_sym) }
      end
    end

    def dns_test_domains
      @dns_test_domains ||= begin
        yaml_path = File.join(File.dirname(__FILE__), '..', 'data', 'dns_test_domains.yml')
        data = YAML.safe_load_file(yaml_path)
        data['domains'].map { |domain| domain['domain'] }
      end
    end
  end
end