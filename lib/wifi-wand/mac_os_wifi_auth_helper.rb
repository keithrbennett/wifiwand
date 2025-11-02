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

    def ensure_helper_installed!(out_stream: $stdout)
      return installed_bundle_path if helper_ready?

      out_stream.puts 'Installing wifiwand macOS helper...' if out_stream
      install_helper_bundle(out_stream: out_stream)
      installed_bundle_path
    end

    def helper_ready?
      executable = installed_executable_path
      File.exist?(executable) && File.executable?(executable)
    end

    def installed_bundle_path
      File.join(versioned_install_dir, BUNDLE_NAME)
    end

    def installed_executable_path
      File.join(installed_bundle_path, 'Contents', 'MacOS', EXECUTABLE_NAME)
    end

    def versioned_install_dir
      File.join(INSTALL_PARENT, helper_version)
    end

    def helper_version
      WifiWand::VERSION
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
      out_stream.puts 'Helper compiled successfully.' if out_stream
    end

    def source_bundle_path
      File.expand_path('../../libexec/macos/wifiwand-helper.app', __dir__)
    end

    def source_swift_path
      File.expand_path('../../libexec/macos/src/wifiwand-helper.swift', __dir__)
    end

    def write_manifest
      FileUtils.mkdir_p(versioned_install_dir)
      File.write(File.join(versioned_install_dir, 'VERSION'), helper_version)
    end

    def helper_info
      {
        version: helper_version,
        installed_bundle: installed_bundle_path,
        installed_executable: installed_executable_path,
        source_bundle: source_bundle_path,
        source_swift: source_swift_path
      }
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
        helper_applicable?
      end

      private

      def execute(command)
        return nil unless helper_applicable?

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

      def helper_applicable?
        return false if @disabled
        return false if ENV.fetch(DISABLE_ENV_KEY, nil) == '1'

        version = macos_version
        return false unless version

        Gem::Version.new(version) >= MINIMUM_HELPER_VERSION
      rescue ArgumentError => e
        log_verbose("unable to parse macOS version '#{version}': #{e.message}")
        false
      end

      def ensure_helper_installed
        return if helper_ready?
        return if @installation_attempted

        @installation_attempted = true
        WifiWand::MacOsWifiAuthHelper.ensure_helper_installed!(out_stream: verbose? ? out_stream : nil)
      rescue StandardError => e
        emit_install_failure(e.message)
        @disabled = true
      end

      def helper_ready?
        WifiWand::MacOsWifiAuthHelper.helper_ready?
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
