# frozen_string_literal: true

# Orchestrates the user-facing macOS setup/repair flow.
# All decision logic lives in MacOsHelperSetup; this class owns output
# formatting, step sequencing, and the ENTER-to-continue prompt so that
# the exe/wifi-wand-macos-setup script stays trivially thin and the flow
# can be exercised in unit tests without spawning a subprocess.
#
# Usage (from the exe):
#   exit WifiWand::MacOsSetupCli.new(argv: ARGV).run

require 'optparse'
require_relative 'mac_os_helper_setup'
require_relative 'mac_os_wifi_auth_helper'

module WifiWand
  class MacOsSetupCli
    STEP_LABELS = {
      install_helper:   'Install wifiwand-helper',
      reinstall_helper: 'Reinstall wifiwand-helper (invalid installation detected)',
      grant_permission: 'Grant location permission in System Settings',
    }.freeze

    # @param argv       [Array<String>]       command-line arguments (e.g. ARGV)
    # @param setup      [MacOsHelperSetup]    injectable for testing; built from out_stream if omitted
    # @param out_stream [IO]                  output sink (default $stdout)
    # @param in_stream  [IO]                  input source for the ENTER prompt (default $stdin)
    def initialize(argv:, setup: nil, out_stream: $stdout, in_stream: $stdin)
      @argv            = argv.dup
      @out_stream      = out_stream
      @in_stream       = in_stream
      @setup           = setup || MacOsHelperSetup.new(out_stream: out_stream)
      @repair_requested = false
    end

    # Run the full setup/repair flow.
    #
    # @return [Integer] exit code (0 = success, 1 = failure)
    def run
      parse_options
      perform_repair if @repair_requested

      status = @setup.check_status
      return 0 if already_complete(status)

      print_header
      print_status_table(status)
      steps = status.steps_needed
      print_steps(steps)
      wait_for_enter
      execute_steps(steps)
      0
    rescue Interrupt
      @out_stream.puts "\nCancelled."
      1
    rescue => e
      @out_stream.puts "\n❌ Error: #{e.message}"
      1
    end

    private

    def parse_options
      OptionParser.new do |opts|
        opts.banner = 'Usage: wifi-wand-macos-setup [--repair]'
        opts.on('--repair', '--reinstall',
          'Force reinstall the helper app and re-run setup') do
          @repair_requested = true
        end
      end.parse!(@argv)
    end

    def perform_repair
      @out_stream.puts 'Reinstalling wifiwand-helper...'
      @setup.reinstall_helper
      @out_stream.puts "✓ Helper reinstalled at: #{MacOsWifiAuthHelper.installed_bundle_path}"
      @out_stream.puts
      @out_stream.puts 'Note: macOS may have revoked the location permission after reinstall.'
      @out_stream.puts 'If prompted, re-grant permission in System Settings.'
      @out_stream.puts
    end

    # Print the "all done" message and return true so the caller can exit 0.
    def already_complete(status)
      return false unless status.setup_complete?

      @out_stream.puts '✅ WifiWand macOS setup is complete! All requirements are satisfied.'
      @out_stream.puts
      @out_stream.puts 'You can use wifi-wand commands:'
      @out_stream.puts '  wifi-wand a              # Show available networks'
      @out_stream.puts '  wifi-wand info           # Show current connection info'
      true
    end

    def print_header
      @out_stream.puts <<~HEADER
        ╔══════════════════════════════════════════════════════════════════╗
        ║         WifiWand macOS Location Permission Setup                 ║
        ╚══════════════════════════════════════════════════════════════════╝

        On macOS 10.15+, apps need location permission to access WiFi
        network names (SSIDs). Without this permission, network names
        appear as '<hidden>' or '<redacted>'.
      HEADER
    end

    def print_status_table(status)
      row = ->(str1 = '', str2 = '') { @out_stream.puts format('  %-40<str1>s %<str2>s', str1:, str2:) }
      separator_line = '=' * 70

      row.()
      row.(separator_line)
      row.('Setup Status:')
      row.(separator_line)
      row.('Helper installed:', status.installed? ? '✓ Yes' : '✗ No')
      if status.installed?
        validity = status.valid? ? '✓ Yes' : '✗ No (repair recommended)'
        row.('Helper valid:', validity)
        row.('Location permission granted:', status.authorized? ? '✓ Yes' : '✗ No')
        unless status.authorized?
          row.('Permission status:', status.permission_message)
        end
      else
        row.('Location permission:', '(will check after installation)')
      end
      row.(separator_line)
    end

    def print_steps(steps)
      @out_stream.puts
      @out_stream.puts 'Steps required:'
      steps.each_with_index { |step, i| @out_stream.puts "  #{i + 1}. #{STEP_LABELS[step]}" }
    end

    def wait_for_enter
      @out_stream.puts
      @out_stream.puts 'Press ENTER to continue (or Ctrl-C to cancel)...'
      @in_stream.gets
    end

    def execute_steps(steps)
      total_steps  = steps.length
      current_step = 0

      if steps.include?(:install_helper)
        current_step += 1
        @out_stream.puts
        @out_stream.puts "[#{current_step}/#{total_steps}] Installing wifiwand-helper..."
        @setup.install_helper
        @out_stream.puts "✓ Helper installed at: #{MacOsWifiAuthHelper.installed_executable_path}"

        # macOS sometimes restores a previously-granted permission after install.
        @out_stream.puts
        @out_stream.puts 'Checking authorization status after installation...'
        post_status = @setup.check_status
        if post_status.authorized?
          @out_stream.puts '✓ Location permission already granted (restored by macOS)'
          steps = post_status.steps_needed
        end

      elsif steps.include?(:reinstall_helper)
        current_step += 1
        @out_stream.puts
        @out_stream.puts "[#{current_step}/#{total_steps}] Reinstalling wifiwand-helper..."
        @setup.reinstall_helper
        @out_stream.puts "✓ Helper reinstalled at: #{MacOsWifiAuthHelper.installed_executable_path}"

        # macOS sometimes preserves authorization across reinstalls.
        @out_stream.puts
        @out_stream.puts 'Checking authorization status after reinstall...'
        post_status = @setup.check_status
        if post_status.authorized?
          @out_stream.puts '✓ Location permission preserved by macOS'
          steps = post_status.steps_needed
        end
      end

      return unless steps.include?(:grant_permission)

      current_step += 1
      @out_stream.puts
      @out_stream.puts "[#{current_step}/#{total_steps}] Setting up location permission..."
      @out_stream.puts 'Opening System Settings → Privacy & Security → Location Services...'
      sleep 1
      @setup.open_location_settings
      print_permission_instructions
    end

    def print_permission_instructions
      @out_stream.puts <<~INSTRUCTIONS

        ╔══════════════════════════════════════════════════════════════════╗
        ║                 Manual Setup Instructions                        ║
        ╚══════════════════════════════════════════════════════════════════╝

        System Settings should now be open. Please follow these steps:

        1. In the Location Services window, scroll down the list
        2. Find 'wifiwand-helper' in the list of apps
        3. Check the box next to 'wifiwand-helper' to enable location access
        4. Close System Settings

        Once enabled, run any wifi-wand command to verify it works:

          wifi-wand a              # Show available networks
          wifi-wand info           # Show current connection info

        If you don't see 'wifiwand-helper' in the list, try running:

          wifi-wand-macos-setup --repair

      INSTRUCTIONS
    end
  end
end
