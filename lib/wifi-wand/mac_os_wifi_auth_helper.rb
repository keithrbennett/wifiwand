# frozen_string_literal: true

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

    def ensure_helper_installed(out_stream: $stdout)
      return installed_bundle_path if File.executable?(installed_executable_path)

      out_stream&.puts 'Installing wifiwand macOS helper...'
      install_helper_bundle(out_stream: out_stream)
      installed_bundle_path
    end

    def install_helper_bundle(out_stream: $stdout)
      FileUtils.mkdir_p(versioned_install_dir)
      FileUtils.rm_rf(installed_bundle_path)
      FileUtils.cp_r(source_bundle_path, installed_bundle_path)
      compile_helper(source_swift_path, installed_executable_path, out_stream: out_stream)
      write_manifest
    end

    def compile_helper(source, destination, out_stream: $stdout)
      FileUtils.mkdir_p(File.dirname(destination))
      command = [
        'swiftc',
        source,
        '-framework', 'Cocoa',
        '-framework', 'CoreLocation',
        '-framework', 'CoreWLAN',
        '-o', destination
      ]
      stdout, stderr, status = Open3.capture3(*command)
      unless status.success?
        raise "Failed to compile WiFi helper (status=#{status.exitstatus}): #{stderr.empty? ? stdout : stderr}"
      end
      FileUtils.chmod(0o755, destination)
      out_stream&.puts 'Helper compiled successfully.'

      # Code sign the helper bundle to enable proper TCC registration
      sign_helper_bundle(destination, out_stream: out_stream)
    end

    def sign_helper_bundle(executable_path, out_stream: $stdout)
      # Get the bundle path from the executable path
      bundle_path = executable_path.split('/Contents/MacOS/').first

      # Require Developer ID - ad-hoc signing doesn't create TCC entries
      identity = ENV['WIFIWAND_CODESIGN_IDENTITY']
      unless identity
        raise <<~ERROR
          WIFIWAND_CODESIGN_IDENTITY environment variable not set.

          The macOS helper requires proper code signing with a Developer ID certificate.
          Ad-hoc signing does not create TCC (permission) database entries, making
          permission management non-functional.

          To sign the helper:
            1. Get an Apple Developer ID certificate (see docs/dev/MACOS_CODE_SIGNING.md)
            2. Set your identity:
               export WIFIWAND_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAM123)"
            3. Recompile the helper:
               bundle exec rake swift:compile_helper

          To find your identity:
            security find-identity -v -p codesigning
        ERROR
      end

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
        @installation_attempted = false
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

        Gem::Version.new(version) >= MINIMUM_HELPER_VERSION
      rescue ArgumentError => e
        log_verbose("unable to parse macOS version '#{version}': #{e.message}")
        false
      end

      private

      def execute(command)
        return nil unless available?

        ensure_helper_installed
        return nil if @disabled

        stdout, stderr, status = Open3.capture3(helper_executable_path, '--command', command)
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
        return if @installation_attempted

        @installation_attempted = true
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
        stream.puts('wifiwand helper: Location Services denied. Run `wifiwand mac authorize` to enable unredacted SSIDs.') if stream
        @location_warning_emitted = true
      end

      def emit_install_failure(detail)
        stream = out_stream || $stdout
        stream.puts("wifiwand helper: failed to install helper (#{detail}).") if stream
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
