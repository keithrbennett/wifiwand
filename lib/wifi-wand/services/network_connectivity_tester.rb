require 'socket'
require 'timeout'
require 'yaml'
require 'ipaddr'

module WifiWand
  class NetworkConnectivityTester
    
    def initialize(verbose: false)
      @verbose = verbose
    end

    # Tests both TCP connectivity to internet hosts and DNS resolution.
    def connected_to_internet?
      tcp_connectivity? && dns_working?
    end

    # Tests TCP connectivity to internet hosts (not localhost)
    def tcp_connectivity?
      test_endpoints = load_tcp_test_endpoints
      
      if @verbose
        endpoints_list = test_endpoints.map { |e| "#{e[:host]}:#{e[:port]}" }.join(', ')
        puts "Testing internet TCP connectivity to: #{endpoints_list}"
      end

      # Test all endpoints in parallel, return as soon as any succeeds
      success_queue = Queue.new
      
      test_endpoints.each do |endpoint|
        Thread.new do
          begin
            Timeout.timeout(2) do
              Socket.tcp(endpoint[:host], endpoint[:port], connect_timeout: 2) do
                success_queue.push(true)
                puts "Successfully connected to #{endpoint[:host]}:#{endpoint[:port]}" if @verbose
              end
            end
          rescue => e
            puts "Failed to connect to #{endpoint[:host]}:#{endpoint[:port]}: #{e.class}" if @verbose
            # Don't push anything on failure
          end
        end
      end
      
      # Wait for first success or overall timeout
      begin
        Timeout.timeout(2.5) do
          # Return as soon as any thread succeeds
          success_queue.pop
        end
      rescue Timeout::Error
        # No success within overall timeout
        false
      end
    end

    # Tests DNS resolution capability
    def dns_working?
      test_domains = load_dns_test_domains
      
      if @verbose
        puts "Testing DNS resolution for domains: #{test_domains.join(', ')}"
      end
      
      # Test all domains in parallel, return as soon as any succeeds
      success_queue = Queue.new
      
      test_domains.each do |domain|
        Thread.new do
          begin
            Timeout.timeout(2) do
              IPSocket.getaddress(domain)
              success_queue.push(true)
              puts "Successfully resolved #{domain}" if @verbose
            end
          rescue => e
            puts "Failed to resolve #{domain}: #{e.class}" if @verbose
            # Don't push anything on failure
          end
        end
      end
      
      # Wait for first success or overall timeout
      begin
        Timeout.timeout(2.5) do
          # Return as soon as any thread succeeds
          success_queue.pop
        end
      rescue Timeout::Error
        # No success within overall timeout
        false
      end
    end

    private

    def load_tcp_test_endpoints
      yaml_path = File.join(File.dirname(__FILE__), '..', 'data', 'tcp_test_endpoints.yml')
      data = YAML.load_file(yaml_path)
      data['endpoints'].map { |endpoint| endpoint.transform_keys(&:to_sym) }
    end

    def load_dns_test_domains
      yaml_path = File.join(File.dirname(__FILE__), '..', 'data', 'dns_test_domains.yml')
      data = YAML.load_file(yaml_path)
      data['domains'].map { |domain| domain['domain'] }
    end
  end
end