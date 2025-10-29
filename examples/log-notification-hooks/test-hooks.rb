#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Automated test suite for WiFi event notification hooks
# Tests all hooks with sample events and validates outputs
#
# Usage: ruby test-hooks.rb
# Or with verbose output: ruby test-hooks.rb -v

require 'json'
require 'tempfile'
require 'fileutils'

# ANSI color codes
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
CYAN = "\033[0;36m"
NC = "\033[0m" # No Color

class HookTestSuite
  attr_reader :verbose, :script_dir, :temp_dir
  attr_accessor :tests_run, :tests_passed, :tests_failed, :tests_skipped

  def initialize(verbose: false)
    @verbose = verbose
    @script_dir = __dir__
    @temp_dir = Dir.mktmpdir
    @tests_run = 0
    @tests_passed = 0
    @tests_failed = 0
    @tests_skipped = 0
  end

  def cleanup
    FileUtils.rm_rf(temp_dir)
  end

  def print_header(text)
    puts "\n#{CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━#{NC}"
    puts "#{CYAN}Testing: #{text}#{NC}"
    puts "#{CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━#{NC}"
  end

  def run_test(test_name, test_cmd, expected_pattern = nil)
    @tests_run += 1

    puts "\n#{YELLOW}Test: #{test_name}#{NC}" if verbose
    puts "Command: #{test_cmd}" if verbose

    output = `#{test_cmd} 2>&1`
    success = Process.last_status.success?

    if !success
      puts "#{RED}✗ FAIL#{NC}: #{test_name} (command failed)"
      puts "Error: #{output}"
      @tests_failed += 1
      return false
    end

    if expected_pattern.nil? || output.include?(expected_pattern)
      puts "#{GREEN}✓ PASS#{NC}: #{test_name}"
      puts "Output: #{output}" if verbose
      @tests_passed += 1
      return true
    else
      puts "#{RED}✗ FAIL#{NC}: #{test_name} (expected pattern not found)"
      puts "Expected: #{expected_pattern}"
      puts "Got: #{output}"
      @tests_failed += 1
      return false
    end
  end

  def skip_test(test_name, reason)
    @tests_run += 1
    @tests_skipped += 1
    puts "#{YELLOW}⊘ SKIP#{NC}: #{test_name} (#{reason})"
  end

  def create_test_events
    events = {
      'event-wifi-on.json' => {
        type: 'wifi_on',
        timestamp: '2025-10-29T14:32:30.000000Z',
        details: {},
        previous_state: {},
        current_state: {}
      },
      'event-wifi-off.json' => {
        type: 'wifi_off',
        timestamp: '2025-10-29T14:32:30.000000Z',
        details: {},
        previous_state: {},
        current_state: {}
      },
      'event-connected.json' => {
        type: 'connected',
        timestamp: '2025-10-29T14:32:30.000000Z',
        details: { network_name: 'TestNetwork' },
        previous_state: {},
        current_state: {}
      },
      'event-disconnected.json' => {
        type: 'disconnected',
        timestamp: '2025-10-29T14:32:30.000000Z',
        details: { network_name: 'TestNetwork' },
        previous_state: {},
        current_state: {}
      },
      'event-internet-on.json' => {
        type: 'internet_on',
        timestamp: '2025-10-29T14:32:30.000000Z',
        details: {},
        previous_state: {},
        current_state: {}
      },
      'event-internet-off.json' => {
        type: 'internet_off',
        timestamp: '2025-10-29T14:32:30.000000Z',
        details: {},
        previous_state: {},
        current_state: {}
      }
    }

    events.each do |filename, event_data|
      File.write(File.join(temp_dir, filename), JSON.generate(event_data))
    end
  end

  def test_syslog_hook
    print_header 'on-wifi-event-syslog.rb'

    hook_path = File.join(script_dir, 'on-wifi-event-syslog.rb')
    unless File.exist?(hook_path)
      skip_test 'syslog hook', 'script not found'
      return
    end

    run_test 'executes without errors',
             "cat '#{File.join(temp_dir, 'event-wifi-on.json')}' | '#{hook_path}' && echo 'success'",
             'success'
  end

  def test_json_log_hook
    print_header 'on-wifi-event-json-log.rb'

    hook_path = File.join(script_dir, 'on-wifi-event-json-log.rb')
    unless File.exist?(hook_path)
      skip_test 'json log hook', 'script not found'
      return
    end

    log_file = File.join(temp_dir, 'test-events.jsonl')
    ENV['WIFIWAND_JSON_LOG_FILE'] = log_file

    run_test 'logs wifi_on event',
             "cat '#{File.join(temp_dir, 'event-wifi-on.json')}' | '#{hook_path}' && cat '#{log_file}'",
             'wifi_on'

    run_test 'logs connected event',
             "cat '#{File.join(temp_dir, 'event-connected.json')}' | '#{hook_path}' && cat '#{log_file}'",
             'connected'

    run_test 'logs internet_off event',
             "cat '#{File.join(temp_dir, 'event-internet-off.json')}' | '#{hook_path}' && cat '#{log_file}'",
             'internet_off'

    ENV.delete('WIFIWAND_JSON_LOG_FILE')
  end

  def test_slack_hook
    print_header 'on-wifi-event-slack.rb'

    hook_path = File.join(script_dir, 'on-wifi-event-slack.rb')
    unless File.exist?(hook_path)
      skip_test 'slack hook', 'script not found'
      return
    end

    if ENV['SLACK_WEBHOOK_URL'].nil?
      skip_test 'slack hook', 'SLACK_WEBHOOK_URL not set'
      return
    end

    run_test 'executes without errors',
             "cat '#{File.join(temp_dir, 'event-wifi-on.json')}' | '#{hook_path}' && echo 'success'",
             'success'
  end

  def test_webhook_hook
    print_header 'on-wifi-event-webhook.rb'

    hook_path = File.join(script_dir, 'on-wifi-event-webhook.rb')
    unless File.exist?(hook_path)
      skip_test 'webhook hook', 'script not found'
      return
    end

    if ENV['WEBHOOK_URL'].nil?
      skip_test 'webhook hook', 'WEBHOOK_URL not set'
      return
    end

    run_test 'executes without errors',
             "cat '#{File.join(temp_dir, 'event-internet-on.json')}' | timeout 5 '#{hook_path}' && echo 'success'",
             'success'
  end

  def test_macos_notify_hook
    print_header 'on-wifi-event-macos-notify.rb'

    hook_path = File.join(script_dir, 'on-wifi-event-macos-notify.rb')
    unless File.exist?(hook_path)
      skip_test 'macOS notify', 'script not found'
      return
    end

    unless RUBY_PLATFORM.include?('darwin')
      skip_test 'macOS notify', 'not on macOS'
      return
    end

    run_test 'executes without errors',
             "cat '#{File.join(temp_dir, 'event-wifi-on.json')}' | '#{hook_path}' && echo 'success'",
             'success'
  end

  def test_gnome_notify_hook
    print_header 'on-wifi-event-gnome-notify.rb'

    hook_path = File.join(script_dir, 'on-wifi-event-gnome-notify.rb')
    unless File.exist?(hook_path)
      skip_test 'GNOME notify', 'script not found'
      return
    end

    run_test 'executes without errors',
             "cat '#{File.join(temp_dir, 'event-wifi-on.json')}' | '#{hook_path}' && echo 'success'",
             'success'
  end

  def test_kde_notify_hook
    print_header 'on-wifi-event-kde-notify.rb'

    hook_path = File.join(script_dir, 'on-wifi-event-kde-notify.rb')
    unless File.exist?(hook_path)
      skip_test 'KDE notify', 'script not found'
      return
    end

    run_test 'executes without errors',
             "cat '#{File.join(temp_dir, 'event-wifi-on.json')}' | '#{hook_path}' && echo 'success'",
             'success'
  end

  def test_multi_hook
    print_header 'on-wifi-event-multi.rb'

    hook_path = File.join(script_dir, 'on-wifi-event-multi.rb')
    unless File.exist?(hook_path)
      skip_test 'multi hook', 'script not found'
      return
    end

    # Test with minimal configuration
    ENV['WIFIWAND_MULTI_NOTIFY'] = 'false'
    ENV['WIFIWAND_MULTI_JSON_LOG'] = 'false'
    ENV['WIFIWAND_MULTI_HOOK_DIR'] = script_dir

    run_test 'executes without errors',
             "cat '#{File.join(temp_dir, 'event-wifi-on.json')}' | '#{hook_path}' && echo 'success'",
             'success'

    ENV.delete('WIFIWAND_MULTI_NOTIFY')
    ENV.delete('WIFIWAND_MULTI_JSON_LOG')
    ENV.delete('WIFIWAND_MULTI_HOOK_DIR')
  end

  def test_permissions
    print_header 'Hook File Permissions'

    Dir.glob(File.join(script_dir, '*.rb')).each do |hook|
      next unless File.file?(hook)

      name = File.basename(hook)
      if File.executable?(hook)
        puts "#{GREEN}✓#{NC}: #{name} is executable"
        @tests_passed += 1
      else
        puts "#{RED}✗#{NC}: #{name} is NOT executable (run: chmod +x #{hook})"
        @tests_failed += 1
      end
      @tests_run += 1
    end
  end

  def test_json_validity
    print_header 'JSON Validity'

    Dir.glob(File.join(temp_dir, 'event-*.json')).each do |json_file|
      name = File.basename(json_file)
      begin
        JSON.parse(File.read(json_file))
        puts "#{GREEN}✓ PASS#{NC}: valid JSON: #{name}"
        @tests_passed += 1
        @tests_run += 1
      rescue JSON::ParserError => e
        puts "#{RED}✗ FAIL#{NC}: invalid JSON: #{name}"
        puts "Error: #{e.message}"
        @tests_failed += 1
        @tests_run += 1
      end
    end
  end

  def check_dependencies
    puts "\n#{CYAN}Checking dependencies...#{NC}"
    %w[ruby].each do |cmd|
      if system("which #{cmd} > /dev/null 2>&1")
        puts "#{GREEN}✓#{NC} #{cmd} installed"
      else
        puts "#{YELLOW}⊘#{NC} #{cmd} not installed"
      end
    end
  end

  def run_all_tests
    puts "#{CYAN}╔══════════════════════════════════════════════════╗#{NC}"
    puts "#{CYAN}║  WiFi Event Hook Automated Test Suite            ║#{NC}"
    puts "#{CYAN}╚══════════════════════════════════════════════════╝#{NC}"

    check_dependencies
    create_test_events

    test_permissions
    test_json_validity
    test_syslog_hook
    test_json_log_hook
    test_slack_hook
    test_webhook_hook
    test_macos_notify_hook
    test_gnome_notify_hook
    test_kde_notify_hook
    test_multi_hook

    print_summary
  end

  def print_summary
    puts "\n#{CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━#{NC}"
    puts "#{CYAN}Test Summary#{NC}"
    puts "#{CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━#{NC}"
    puts "Total tests run: #{tests_run}"
    puts "Passed: #{GREEN}#{tests_passed}#{NC}"
    puts "Failed: #{RED}#{tests_failed}#{NC}"
    puts "Skipped: #{YELLOW}#{tests_skipped}#{NC}"

    if tests_failed == 0
      puts "\n#{GREEN}✓ All tests passed!#{NC}"
      exit 0
    else
      puts "\n#{RED}✗ Some tests failed#{NC}"
      exit 1
    end
  end
end

# Main execution
verbose_mode = ARGV.include?('-v')
suite = HookTestSuite.new(verbose: verbose_mode)

begin
  suite.run_all_tests
ensure
  suite.cleanup
end
