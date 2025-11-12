# frozen_string_literal: true
# Manages the lifecycle of the macOS Wi-Fi helper app that runs privileged Swift code.
# The module installs, compiles, and signs the helper bundle per WifiWand version so
# network queries can bypass TCC redactions on Sonoma+ while remaining opt-in via env flag.
# Entry points:
#   * WifiWand::MacOsWifiAuthHelper.ensure_helper_installed -> installs/validates the helper bundle.
#   * Client#connected_network_name -> runs the helper's `current-network` command and returns the SSID.
#   * Client#scan_networks -> runs the helper's `scan-networks` command and returns network metadata.
#   * Client#available? -> tells callers when the helper can safely be invoked on the current host.

require 'fileutils'
require 'json'
require 'open3'
require 'rubygems/version'
require_relative 'version'

module WifiWand
  module MacOsWifiAuthHelper
    BUNDLE_NAME = 'wifiwand-helper.app'
    EXECUTABLE_NAME = 'wifiwand-helper'
    INSTALL_PARENT = File.join(Dir.home, 'Library', 'Application Support', 'WifiWand')
    # Only enable the helper on macOS Sonoma (14.0) and newer where redactions occur
    MINIMUM_HELPER_VERSION = Gem::Version.new('14.0')
    # Allows power users/CI to opt out of helper usage via environment flag
    DISABLE_ENV_KEY = 'WIFIWAND_DISABLE_MAC_HELPER'

    module_function

    # Path and Configuration Methods
    # ==============================

    # Returns the version string used for the helper installation
    #
    # @return [String] WifiWand gem version (e.g., "1.2.3")
    def helper_version
      WifiWand::VERSION
    end

    # Returns the path to the Swift source file in the gem's libexec directory
    #
    # @return [String] absolute path to wifiwand-helper.swift source file
    #   Example: /path/to/gem/libexec/macos/src/wifiwand-helper.swift
    def source_swift_path
      File.expand_path('../../libexec/macos/src/wifiwand-helper.swift', __dir__)
    end

    # Returns the path to the app bundle template in the gem's libexec directory
    #
    # @return [String] absolute path to the bundle template directory
    #   Example: /path/to/gem/libexec/macos/wifiwand-helper.app
    def source_bundle_path
      File.expand_path('../../libexec/macos/wifiwand-helper.app', __dir__)
    end

    # Returns the versioned installation directory in user's Library folder
    #
    # @return [String] absolute path to version-specific installation directory
    #   Example: ~/Library/Application Support/WifiWand/1.2.3
    def versioned_install_dir
      File.join(INSTALL_PARENT, helper_version)
    end

    # Returns the path to the installed app bundle in user's Library folder
    #
    # @return [String] absolute path to the installed .app bundle
    #   Example: ~/Library/Application Support/WifiWand/1.2.3/wifiwand-helper.app
    def installed_bundle_path
      File.join(versioned_install_dir, BUNDLE_NAME)
    end

    # Returns the path to the compiled executable inside the installed bundle
    #
    # @return [String] absolute path to the executable binary
    #   Example: ~/Library/Application Support/WifiWand/1.2.3/wifiwand-helper.app/Contents/MacOS/wifiwand-helper
    def installed_executable_path
      File.join(installed_bundle_path, 'Contents', 'MacOS', EXECUTABLE_NAME)
    end

    # Returns a hash containing all helper paths and version information
    #
    # @return [Hash] helper configuration with keys:
    #   - :version - helper version string
    #   - :installed_bundle - path to installed .app bundle
    #   - :installed_executable - path to compiled executable
    #   - :source_bundle - path to bundle template in gem
    #   - :source_swift - path to Swift source in gem
    def helper_info
      {
        version: helper_version,
        installed_bundle: installed_bundle_path,
        installed_executable: installed_executable_path,
        source_bundle: source_bundle_path,
        source_swift: source_swift_path
      }
    end

    # Installation and Compilation Methods
    # =====================================

    # Verifies the helper installation is valid and not corrupted
    #
    # @return [Boolean] true if helper is properly installed and executable
    def helper_installed_and_valid?
      return false unless File.executable?(installed_executable_path)
      return false unless File.exist?(File.join(installed_bundle_path, 'Contents', 'Info.plist'))

      # Quick validation: try to execute with --help flag
      stdout, _stderr, status = Open3.capture3(installed_executable_path, '--help')
      status.success? && !stdout.strip.empty?
    rescue Errno::ENOENT
      false
    end

    # Copies the pre-signed helper bundle into ~/Library and immediately re-validates it.
    # Concurrent installs may briefly leave the bundle incomplete, so we trust the follow-up
    # validation (and let callers retry) instead of attempting multiple installs here.
    def ensure_helper_installed(out_stream: $stdout)
      return installed_bundle_path if helper_installed_and_valid?

      out_stream&.puts 'Installing wifiwand macOS helper...'
      install_helper_bundle(out_stream: out_stream)

      # Verify installation succeeded - if not, likely concurrent corruption
      unless helper_installed_and_valid?
        raise "Helper installation failed validation. If running multiple processes concurrently, try again."
      end

      installed_bundle_path
    end

    def install_helper_bundle(out_stream: $stdout)
      FileUtils.mkdir_p(versioned_install_dir)
      FileUtils.rm_rf(installed_bundle_path)
      FileUtils.cp_r(source_bundle_path, installed_bundle_path)
      FileUtils.chmod(0o755, installed_executable_path)
      out_stream&.puts 'Helper bundle installed from pre-signed binary.' if out_stream
      write_manifest
    end

    def compile_helper(source, destination, out_stream: $stdout)
      FileUtils.mkdir_p(File.dirname(destination))

      # Compile for both architectures to create a universal binary
      arm_binary = "#{destination}.arm64"
      x86_binary = "#{destination}.x86_64"

      out_stream&.puts 'Compiling for arm64 (Apple Silicon)...'
      compile_for_arch(source, arm_binary, 'arm64-apple-macos14.0')

      out_stream&.puts 'Compiling for x86_64 (Intel)...'
      compile_for_arch(source, x86_binary, 'x86_64-apple-macos14.0')

      # Create universal binary with lipo
      out_stream&.puts 'Creating universal binary...'
      command = ['lipo', '-create', arm_binary, x86_binary, '-output', destination]
      stdout, stderr, status = Open3.capture3(*command)

      unless status.success?
        raise "Failed to create universal binary (status=#{status.exitstatus}): #{stderr.empty? ? stdout : stderr}"
      end

      # Clean up individual architecture binaries
      FileUtils.rm_f([arm_binary, x86_binary])

      FileUtils.chmod(0o755, destination)
      out_stream&.puts 'Universal helper compiled successfully (arm64 + x86_64).'

      # Code sign the helper bundle to enable proper TCC registration
      sign_helper_bundle(destination, out_stream: out_stream)
    end

    def compile_for_arch(source, destination, target)
      command = [
        'swiftc',
        source,
        '-target', target,
        '-framework', 'Cocoa',
        '-framework', 'CoreLocation',
        '-framework', 'CoreWLAN',
        '-o', destination
      ]
      stdout, stderr, status = Open3.capture3(*command)

      unless status.success?
        raise "Failed to compile for #{target} (status=#{status.exitstatus}): #{stderr.empty? ? stdout : stderr}"
      end
    end

    def sign_helper_bundle(executable_path, out_stream: $stdout)
      # Get the bundle path from the executable path
      bundle_path = executable_path.split('/Contents/MacOS/').first

      # Use environment variable or default to Keith's Developer ID
      identity = ENV['WIFIWAND_CODESIGN_IDENTITY'] ||
                 "Developer ID Application: Bennett Business Solutions, Inc. (97P9SZU9GG)"

      # Path to entitlements file
      entitlements_path = File.expand_path('../../libexec/macos/wifiwand-helper.entitlements', __dir__)

      command = [
        'codesign',
        '--force',
        '--sign', identity,
        '--deep',
        '--options', 'runtime',
        '--entitlements', entitlements_path,
        '--timestamp',
        bundle_path
      ]

      out_stream&.puts "Signing helper bundle with Developer ID '#{identity}'..."
      stdout, stderr, status = Open3.capture3(*command)

      unless status.success?
        raise "Failed to code sign helper bundle (status=#{status.exitstatus}): #{stderr.empty? ? stdout : stderr}"
      end

      out_stream&.puts 'Helper bundle signed successfully.'
    end

    def write_manifest
      FileUtils.mkdir_p(versioned_install_dir)
      File.write(File.join(versioned_install_dir, 'VERSION'), helper_version)
    end

    class Client
      def initialize(out_stream_proc:, verbose_proc:, macos_version_proc:)
        @out_stream_proc = out_stream_proc
        @verbose_proc = verbose_proc
        @macos_version_proc = macos_version_proc
        @location_warning_emitted = false
        @disabled = false
      end

      def connected_network_name
        payload = execute('current-network')
        payload&.fetch('ssid', nil)
      end

      def scan_networks
        payload = execute('scan-networks')
        return [] unless payload

        payload.fetch('networks', [])
      end

      def available?
        return false if @disabled
        return false if ENV.fetch(DISABLE_ENV_KEY, nil) == '1'

        version = macos_version
        return false unless version

        sanitized_version = sanitize_version_string(version)
        unless sanitized_version
          log_verbose("macOS version '#{version}' does not match expected format")
          return false
        end

        Gem::Version.new(sanitized_version) >= MINIMUM_HELPER_VERSION
      rescue ArgumentError => e
        log_verbose("unable to parse macOS version '#{sanitized_version || version}': #{e.message}")
        false
      end

      private

      def sanitize_version_string(version)
        return nil unless version

        version_string = version.to_s.strip
        match = version_string.match(/\d+(?:\.\d+)*/)
        match&.[](0)
      end

      def execute(command)
        return nil unless available?

        ensure_helper_installed
        return nil if @disabled

        stdout, stderr, status = Open3.capture3(helper_executable_path, command)
        unless status.success?
          log_verbose("helper exited with status #{status.exitstatus}: #{stderr.strip}")
          return nil
        end

        payload = parse_json(stdout)
        return nil unless payload

        if payload['status'] == 'error'
          handle_error(payload['error'])
          return nil
        end

        payload
      rescue Errno::ENOENT => e
        log_verbose("helper executable missing: #{e.message}")
        nil
      rescue StandardError => e
        log_verbose("helper command '#{command}' failed: #{e.message}")
        nil
      end

      def ensure_helper_installed
        return if File.executable?(helper_executable_path)
        return if @disabled

        log_verbose('helper not installed; running installer')
        WifiWand::MacOsWifiAuthHelper.ensure_helper_installed(out_stream: verbose? ? out_stream : nil)
      rescue StandardError => e
        emit_install_failure(e.message)
        @disabled = true
      end

      def helper_executable_path
        WifiWand::MacOsWifiAuthHelper.installed_executable_path
      end

      def parse_json(text)
        JSON.parse(text)
      rescue JSON::ParserError => e
        log_verbose("failed to parse helper JSON: #{e.message}")
        nil
      end

      def handle_error(message)
        return unless message

        if message.downcase.include?('location services denied')
          emit_location_warning
        else
          log_verbose("helper error: #{message}")
        end
      end

      def emit_location_warning
        return if @location_warning_emitted

        stream = out_stream || $stdout
        stream.puts('wifiwand helper: Location Services denied. Run `bundle exec rake mac:helper_location_permission_allow` to enable unredacted SSIDs.') if stream
        @location_warning_emitted = true
      end

      def emit_install_failure(detail)
        stream = out_stream || $stdout
        stream.puts("wifiwand helper: failed to install helper (#{detail}). Helper disabled until the next run.") if stream
      end

      def log_verbose(message)
        return unless verbose?

        stream = out_stream || $stdout
        stream.puts("wifiwand helper: #{message}") if stream
      end

      def macos_version
        @macos_version_proc&.call
      end

      def out_stream
        @out_stream_proc&.call
      end

      def verbose?
        !!(@verbose_proc && @verbose_proc.call)
      end
    end
  end
end
