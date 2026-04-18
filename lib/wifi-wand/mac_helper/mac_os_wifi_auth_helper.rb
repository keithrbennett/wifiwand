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
require 'securerandom'
require 'tmpdir'
require 'digest'
require 'pathname'
require_relative '../version'

module WifiWand
  module MacOsWifiAuthHelper
    BUNDLE_NAME = 'wifiwand-helper.app'
    EXECUTABLE_NAME = 'wifiwand-helper'
    INSTALL_PARENT = File.join(Dir.home, 'Library', 'Application Support', 'WifiWand')
    # Only enable the helper on macOS Sonoma (14.0) and newer where redactions occur
    MINIMUM_HELPER_VERSION = Gem::Version.new('14.0')
    # Allows power users/CI to opt out of helper usage via environment flag
    DISABLE_ENV_KEY = 'WIFIWAND_DISABLE_MAC_HELPER'
    HELPER_COMMAND_TIMEOUT_SECONDS =
      (ENV['WIFIWAND_HELPER_TIMEOUT_SECONDS'] || 3.0).to_f
    HELPER_TERMINATION_WAIT_SECONDS = 0.25
    MANIFEST_FILENAME = 'INSTALL_MANIFEST.json'
    SOURCE_MANIFEST_FILENAME = 'wifiwand-helper.source-manifest.json'

    module_function

    # Path and Configuration Methods
    # ==============================

    # Returns the version string used for the helper installation
    #
    # @return [String] WifiWand gem version (e.g., "1.2.3")
    def helper_version = WifiWand::VERSION

    # Returns the path to the Swift source file in the gem's libexec directory
    #
    # @return [String] absolute path to wifiwand-helper.swift source file
    #   Example: /path/to/gem/libexec/macos/src/wifiwand-helper.swift
    def source_swift_path = File.expand_path('../../../libexec/macos/src/wifiwand-helper.swift', __dir__)

    # Returns the path to the app bundle template in the gem's libexec directory
    #
    # @return [String] absolute path to the bundle template directory
    #   Example: /path/to/gem/libexec/macos/wifiwand-helper.app
    def source_bundle_path = File.expand_path('../../../libexec/macos/wifiwand-helper.app', __dir__)

    # Returns the path to the source attestation manifest committed with the helper bundle.
    #
    # @return [String] absolute path to the helper source manifest
    def source_bundle_manifest_path =
      File.expand_path("../../../libexec/macos/#{SOURCE_MANIFEST_FILENAME}", __dir__)

    # Returns the versioned installation directory in user's Library folder
    #
    # @return [String] absolute path to version-specific installation directory
    #   Example: ~/Library/Application Support/WifiWand/1.2.3
    def versioned_install_dir = File.join(INSTALL_PARENT, helper_version)

    # Returns the path to the installed app bundle in user's Library folder
    #
    # @return [String] absolute path to the installed .app bundle
    #   Example: ~/Library/Application Support/WifiWand/1.2.3/wifiwand-helper.app
    def installed_bundle_path = File.join(versioned_install_dir, BUNDLE_NAME)

    # Returns the path to the compiled executable inside the installed bundle
    #
    # @return [String] absolute path to the executable binary
    #   Example: ~/Library/Application Support/WifiWand/1.2.3/wifiwand-helper.app/Contents/MacOS/wifiwand-helper
    def installed_executable_path = File.join(installed_bundle_path, 'Contents', 'MacOS', EXECUTABLE_NAME)

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
        version:              helper_version,
        installed_bundle:     installed_bundle_path,
        installed_executable: installed_executable_path,
        source_bundle:        source_bundle_path,
        source_swift:         source_swift_path,
      }
    end

    # Installation and Compilation Methods
    # =====================================

    # Verifies the helper installation is valid and not corrupted
    #
    # @return [Boolean] true if helper is properly installed and executable
    def helper_installed_and_valid?
      helper_bundle_valid?(installed_bundle_path) && installed_bundle_current?
    end

    # Copies the pre-signed helper bundle into ~/Library and immediately re-validates it.
    # Concurrent installs may briefly leave the bundle incomplete, so we trust the follow-up
    # validation (and let callers retry) instead of attempting multiple installs here.
    def ensure_helper_installed(out_stream: $stdout)
      return installed_bundle_path if helper_installed_and_valid?

      install_helper_bundle(out_stream: out_stream)

      unless helper_installed_and_valid?
        raise 'Helper installation failed validation after installation.'
      end

      installed_bundle_path
    end

    def install_helper_bundle(out_stream: $stdout)
      with_install_lock do
        return installed_bundle_path if helper_installed_and_valid?

        out_stream&.puts 'Installing wifiwand macOS helper...'

        Dir.mktmpdir("#{BUNDLE_NAME}.tmp-", versioned_install_dir) do |temp_dir|
          staged_bundle_path = File.join(temp_dir, BUNDLE_NAME)
          stage_helper_bundle(staged_bundle_path)

          unless helper_bundle_valid?(staged_bundle_path)
            raise 'Staged helper installation failed validation.'
          end

          publish_staged_bundle(staged_bundle_path)
          write_manifest
        end
      end

      out_stream&.puts 'Helper bundle installed from pre-signed binary.' if out_stream
      installed_bundle_path
    end

    def install_lock_path = File.join(versioned_install_dir, '.install.lock')

    def install_manifest_path = File.join(versioned_install_dir, MANIFEST_FILENAME)

    def helper_bundle_valid?(bundle_path)
      executable_path = File.join(bundle_path, 'Contents', 'MacOS', EXECUTABLE_NAME)
      return false unless File.executable?(executable_path)
      return false unless File.exist?(File.join(bundle_path, 'Contents', 'Info.plist'))

      helper_result = run_bounded_helper_command(executable_path, 'help')
      return false unless helper_result

      # A successful help probe is the contract; different helper builds may write
      # usage text to stdout or stderr, so treat either stream as acceptable output.
      return false unless helper_result[:status].success?

      command_output = "#{helper_result[:stdout]}#{helper_result[:stderr]}".strip
      !command_output.empty?
    end

    def installed_bundle_current?
      manifest = read_install_manifest

      if manifest
        manifest['helper_version'] == helper_version &&
          manifest['bundle_fingerprint'] == bundle_fingerprint(installed_bundle_path) &&
          manifest['bundle_fingerprint'] == bundle_fingerprint(source_bundle_path)
      else
        false
      end
    end

    def source_bundle_current?
      manifest = read_source_bundle_manifest

      if manifest
        manifest['helper_version'] == helper_version &&
          manifest['source_sha256'] == source_swift_fingerprint &&
          manifest['bundle_fingerprint'] == bundle_fingerprint(source_bundle_path)
      else
        false
      end
    end

    def verify_source_bundle_current!
      source_bundle_current? || raise(source_bundle_mismatch_message)
    end

    def run_bounded_helper_command(executable_path, command, on_timeout: nil)
      Open3.popen3(executable_path, command) do |stdin, stdout, stderr, wait_thr|
        stdin.close
        stdout_reader = Thread.new { stdout.read }
        stderr_reader = Thread.new { stderr.read }
        wait_result = wait_thr.join(HELPER_COMMAND_TIMEOUT_SECONDS)
        unless wait_result
          on_timeout&.call(command, HELPER_COMMAND_TIMEOUT_SECONDS)
          terminate_helper_process(wait_thr)
          return nil
        end

        {
          stdout: stdout_reader.value,
          stderr: stderr_reader.value,
          status: wait_thr.value,
        }
      ensure
        stdout&.close unless stdout&.closed?
        stderr&.close unless stderr&.closed?
        stdout_reader&.join
        stderr_reader&.join
      end
    rescue Errno::ENOENT
      nil
    end

    def terminate_helper_process(wait_thr)
      pid = wait_thr.pid
      Process.kill('TERM', pid)
      return if helper_exited_within_grace_period?(wait_thr)
      return unless wait_thr.alive?

      Process.kill('KILL', pid)
      helper_exited_within_grace_period?(wait_thr)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def helper_exited_within_grace_period?(wait_thr)
      !!wait_thr.join(HELPER_TERMINATION_WAIT_SECONDS)
    end

    def with_install_lock
      FileUtils.mkdir_p(versioned_install_dir)

      File.open(install_lock_path, File::RDWR | File::CREAT, 0o644) do |lock_file|
        lock_file.flock(File::LOCK_EX)
        yield
      ensure
        lock_file.flock(File::LOCK_UN)
      end
    end

    def stage_helper_bundle(staged_bundle_path)
      FileUtils.cp_r(source_bundle_path, staged_bundle_path)
      staged_executable_path = File.join(staged_bundle_path, 'Contents', 'MacOS', EXECUTABLE_NAME)
      FileUtils.chmod(0o755, staged_executable_path)
    end

    def publish_staged_bundle(staged_bundle_path)
      publish_token = unique_publish_token
      release_bundle_path = bundle_release_path(publish_token)
      File.rename(staged_bundle_path, release_bundle_path)

      begin
        publish_release_symlink(release_bundle_path, publish_token)
      rescue
        FileUtils.rm_rf(release_bundle_path)
        raise
      end
    end

    def publish_release_symlink(release_bundle_path, publish_token)
      symlink_path = staged_bundle_symlink_path(publish_token)
      File.symlink(File.basename(release_bundle_path), symlink_path)

      if File.symlink?(installed_bundle_path)
        previous_release_path = resolved_installed_bundle_target
        File.rename(symlink_path, installed_bundle_path)
        cleanup_previous_release(previous_release_path)
        return
      end

      if File.exist?(installed_bundle_path)
        FileUtils.rm_f(symlink_path) if File.symlink?(symlink_path)
        migrate_legacy_bundle_to_release(release_bundle_path, publish_token)
        return
      end

      File.rename(symlink_path, installed_bundle_path)
    rescue
      FileUtils.rm_f(symlink_path) if File.symlink?(symlink_path)
      raise
    end

    def migrate_legacy_bundle_to_release(release_bundle_path, publish_token)
      backup_paths = backup_legacy_bundle_metadata(publish_token)
      sync_legacy_bundle_metadata(release_bundle_path, publish_token)
      switch_legacy_bundle_executable(release_bundle_path, publish_token)
    rescue
      restore_legacy_bundle_metadata(backup_paths, publish_token)
      raise
    ensure
      cleanup_legacy_bundle_metadata_backups(backup_paths) if defined?(backup_paths)
    end

    def bundle_release_path(publish_token) =
      File.join(versioned_install_dir, ".#{BUNDLE_NAME}.release-#{publish_token}")

    def staged_bundle_symlink_path(publish_token) = "#{installed_bundle_path}.link-#{publish_token}"

    def legacy_executable_symlink_path(publish_token) = "#{installed_executable_path}.link-#{publish_token}"

    def legacy_info_plist_path = File.join(installed_bundle_path, 'Contents', 'Info.plist')

    def legacy_code_resources_path =
      File.join(installed_bundle_path, 'Contents', '_CodeSignature', 'CodeResources')

    def resolved_installed_bundle_target
      return unless File.symlink?(installed_bundle_path)

      File.expand_path(File.readlink(installed_bundle_path), versioned_install_dir)
    end

    def cleanup_previous_release(previous_release_path)
      return unless previous_release_path
      return unless previous_release_path.start_with?("#{versioned_install_dir}/.#{BUNDLE_NAME}.release-")
      return if previous_release_path == resolved_installed_bundle_target

      FileUtils.rm_rf(previous_release_path)
    end

    def sync_legacy_bundle_metadata(release_bundle_path, publish_token)
      release_info_plist_path = File.join(release_bundle_path, 'Contents', 'Info.plist')
      staged_info_plist_path = "#{legacy_info_plist_path}.tmp-#{publish_token}"
      release_code_resources_path =
        File.join(release_bundle_path, 'Contents', '_CodeSignature', 'CodeResources')
      staged_code_resources_path = "#{legacy_code_resources_path}.tmp-#{publish_token}"

      FileUtils.mkdir_p(File.dirname(legacy_info_plist_path))
      FileUtils.cp(release_info_plist_path, staged_info_plist_path)
      File.rename(staged_info_plist_path, legacy_info_plist_path)

      FileUtils.mkdir_p(File.dirname(legacy_code_resources_path))
      FileUtils.cp(release_code_resources_path, staged_code_resources_path)
      File.rename(staged_code_resources_path, legacy_code_resources_path)
    ensure
      FileUtils.rm_f(staged_info_plist_path) if defined?(staged_info_plist_path)
      FileUtils.rm_f(staged_code_resources_path) if defined?(staged_code_resources_path)
    end

    def backup_legacy_bundle_metadata(publish_token)
      {
        info_plist:     backup_legacy_metadata_file(legacy_info_plist_path, publish_token),
        code_resources: backup_legacy_metadata_file(legacy_code_resources_path, publish_token),
      }
    end

    def backup_legacy_metadata_file(path, publish_token)
      return unless File.exist?(path)

      backup_path = "#{path}.backup-#{publish_token}"
      FileUtils.cp(path, backup_path)
      backup_path
    end

    def restore_legacy_bundle_metadata(backup_paths, publish_token)
      restore_legacy_metadata_file(backup_paths[:info_plist], legacy_info_plist_path, publish_token)
      restore_legacy_metadata_file(backup_paths[:code_resources], legacy_code_resources_path, publish_token)
    end

    def restore_legacy_metadata_file(backup_path, target_path, publish_token)
      return unless backup_path && File.exist?(backup_path)

      staged_restore_path = "#{target_path}.restore-#{publish_token}"
      FileUtils.cp(backup_path, staged_restore_path)
      File.rename(staged_restore_path, target_path)
    ensure
      FileUtils.rm_f(staged_restore_path) if defined?(staged_restore_path)
    end

    def cleanup_legacy_bundle_metadata_backups(backup_paths)
      FileUtils.rm_f(backup_paths.values.compact)
    end

    def switch_legacy_bundle_executable(release_bundle_path, publish_token)
      previous_release_path = resolved_legacy_release_target
      staged_executable_link_path = legacy_executable_symlink_path(publish_token)
      release_executable_path = File.join(release_bundle_path, 'Contents', 'MacOS', EXECUTABLE_NAME)

      File.symlink(release_executable_path, staged_executable_link_path)
      File.rename(staged_executable_link_path, installed_executable_path)
      cleanup_previous_release(previous_release_path)
    rescue
      staged_link_needs_cleanup =
        defined?(staged_executable_link_path) && File.symlink?(staged_executable_link_path)
      FileUtils.rm_f(staged_executable_link_path) if staged_link_needs_cleanup
      raise
    end

    def resolved_legacy_release_target
      return unless File.symlink?(installed_executable_path)

      File.expand_path(File.readlink(installed_executable_path), versioned_install_dir)
        .sub(%r{/Contents/MacOS/[^/]+\z}, '')
    end

    def unique_publish_token = "#{Process.pid}-#{Thread.current.object_id}-#{SecureRandom.hex(6)}"

    def compile_helper(source, destination, out_stream: $stdout)
      FileUtils.mkdir_p(File.dirname(destination))

      # Build universal binary (ARM64 + x86_64) for compatibility with all Macs
      arm64_binary = "#{destination}.arm64"
      x86_64_binary = "#{destination}.x86_64"

      begin
        compile_architecture(source, arm64_binary, 'arm64-apple-macos11', 'ARM64')
        compile_architecture(source, x86_64_binary, 'x86_64-apple-macos11', 'x86_64')
        create_universal_binary(destination, arm64_binary, x86_64_binary)
      ensure
        FileUtils.rm_f([arm64_binary, x86_64_binary])
      end

      FileUtils.chmod(0o755, destination)
      out_stream&.puts 'Helper compiled successfully.'

      # Code sign the helper bundle to enable proper TCC registration
      sign_helper_bundle(destination, out_stream: out_stream)
    end

    def compile_architecture(source, output, target, arch_name)
      command = [
        'swiftc', source,
        '-target', target,
        '-framework', 'Cocoa',
        '-framework', 'CoreLocation',
        '-framework', 'CoreWLAN',
        '-o', output
      ]
      stdout, stderr, status = Open3.capture3(*command)
      return if status.success?

      error_output = stderr.empty? ? stdout : stderr
      raise "Failed to compile #{arch_name} binary (status=#{status.exitstatus}): #{error_output}"
    end

    def create_universal_binary(destination, *architecture_binaries)
      stdout, stderr, status = Open3.capture3('lipo', '-create', '-output', destination,
        *architecture_binaries)
      return if status.success?

      error_output = stderr.empty? ? stdout : stderr
      raise "Failed to create universal binary (status=#{status.exitstatus}): #{error_output}"
    end

    def sign_helper_bundle(executable_path, out_stream: $stdout)
      # Get the bundle path from the executable path
      bundle_path = executable_path.split('/Contents/MacOS/').first

      # Use environment variable or default to Keith's Developer ID
      identity = ENV['WIFIWAND_CODESIGN_IDENTITY'] ||
        'Developer ID Application: Bennett Business Solutions, Inc. (97P9SZU9GG)'

      # Path to entitlements file
      entitlements_path = File.expand_path('../../../libexec/macos/wifiwand-helper.entitlements', __dir__)

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
        raise "Failed to code sign helper bundle (status=#{status.exitstatus}): " \
          "#{stderr.empty? ? stdout : stderr}"
      end

      out_stream&.puts 'Helper bundle signed successfully.'
    end

    def write_source_bundle_manifest
      File.write(source_bundle_manifest_path, JSON.pretty_generate(source_bundle_manifest_payload))
    end

    def source_bundle_manifest_payload
      {
        'helper_version'     => helper_version,
        'source_path'        => relative_helper_path(source_swift_path),
        'source_sha256'      => source_swift_fingerprint,
        'bundle_path'        => relative_helper_path(source_bundle_path),
        'bundle_fingerprint' => bundle_fingerprint(source_bundle_path),
      }
    end

    def read_source_bundle_manifest
      if File.exist?(source_bundle_manifest_path)
        JSON.parse(File.read(source_bundle_manifest_path))
      end
    rescue JSON::ParserError
      nil
    end

    def write_manifest
      FileUtils.mkdir_p(versioned_install_dir)
      File.write(File.join(versioned_install_dir, 'VERSION'), helper_version)
      File.write(install_manifest_path, JSON.pretty_generate(
        {
          'helper_version'     => helper_version,
          'bundle_fingerprint' => bundle_fingerprint(source_bundle_path),
        }
      ))
    end

    def read_install_manifest
      if File.exist?(install_manifest_path)
        JSON.parse(File.read(install_manifest_path))
      end
    rescue JSON::ParserError
      nil
    end

    def bundle_fingerprint(bundle_path)
      digest = Digest::SHA256.new

      tracked_bundle_files(bundle_path).each do |path|
        digest << File.basename(path)
        digest << "\0"
        digest << File.read(path)
        digest << "\0"
      end

      digest.hexdigest
    end

    def source_swift_fingerprint = Digest::SHA256.file(source_swift_path).hexdigest

    def tracked_bundle_files(bundle_path)
      [
        File.join(bundle_path, 'Contents', 'Info.plist'),
        File.join(bundle_path, 'Contents', '_CodeSignature', 'CodeResources'),
        File.join(bundle_path, 'Contents', 'MacOS', EXECUTABLE_NAME),
      ]
    end

    def source_bundle_mismatch_message
      "Shipped macOS helper bundle is out of sync with #{relative_helper_path(source_swift_path)}. " \
        'Run `bundle exec rake swift:compile` or `bin/mac-helper build` to rebuild the signed bundle ' \
        "and refresh #{relative_helper_path(source_bundle_manifest_path)}."
    end

    def relative_helper_path(path)
      repo_root = File.expand_path('../../..', __dir__)
      Pathname.new(path).relative_path_from(Pathname.new(repo_root)).to_s
    end

    HelperQueryResult = Struct.new(
      :payload,
      :location_services_blocked,
      :error_message,
      keyword_init: true
    ) do
      def location_services_blocked? = !!location_services_blocked
    end

    class Client
      HELPER_COMMAND_TIMEOUT_SECONDS = MacOsWifiAuthHelper::HELPER_COMMAND_TIMEOUT_SECONDS
      HELPER_TERMINATION_WAIT_SECONDS = MacOsWifiAuthHelper::HELPER_TERMINATION_WAIT_SECONDS
      attr_reader :last_error_message

      def initialize(out_stream_proc:, verbose_proc:, macos_version_proc:)
        @out_stream_proc = out_stream_proc
        @verbose_proc = verbose_proc
        @macos_version_proc = macos_version_proc
        @location_warning_emitted = false
        @helper_install_verified = false
        @disabled = false
        @last_error_message = nil
      end

      def connected_network_name
        result = execute('current-network')
        ssid = result.payload&.fetch('ssid', nil)
        HelperQueryResult.new(
          payload:                   ssid,
          location_services_blocked: result.location_services_blocked,
          error_message:             result.error_message
        )
      end

      def scan_networks
        result = execute('scan-networks')
        networks = result.payload&.fetch('networks', []) || []
        HelperQueryResult.new(
          payload:                   networks,
          location_services_blocked: result.location_services_blocked,
          error_message:             result.error_message
        )
      end

      def available?
        return false if helper_disabled?

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

      def location_services_blocked?
        return false unless @last_error_message

        @last_error_message.downcase.include?('location services')
      end

      private

      def sanitize_version_string(version)
        return nil unless version

        version_string = version.to_s.strip
        match = version_string.match(/\d+(?:\.\d+)*/)
        match&.[](0)
      end

      def execute(command)
        @last_error_message = nil
        return HelperQueryResult.new unless available?

        ensure_helper_installed
        return HelperQueryResult.new if helper_disabled?

        helper_result = execute_helper_command(command)
        return HelperQueryResult.new unless helper_result

        stdout = helper_result[:stdout]
        stderr = helper_result[:stderr]
        status = helper_result[:status]
        unless status.success?
          log_verbose("helper exited with status #{status.exitstatus}: #{stderr.strip}")
          return HelperQueryResult.new
        end

        payload = parse_json(stdout)
        return HelperQueryResult.new unless payload

        if payload['status'] == 'error'
          error_msg = payload['error']
          handle_error(error_msg)
          return HelperQueryResult.new(
            location_services_blocked: error_msg&.downcase&.include?('location services'),
            error_message:             error_msg
          )
        end

        HelperQueryResult.new(payload: payload)
      rescue Errno::ENOENT => e
        log_verbose("helper executable missing: #{e.message}")
        HelperQueryResult.new
      rescue => e
        log_verbose("helper command '#{command}' failed: #{e.message}")
        HelperQueryResult.new
      end

      def execute_helper_command(command)
        WifiWand::MacOsWifiAuthHelper.run_bounded_helper_command(
          helper_executable_path,
          command,
          on_timeout: ->(timed_out_command, timeout_seconds) do
            log_verbose("helper command '#{timed_out_command}' timed out after #{timeout_seconds}s")
          end
        )
      end

      def terminate_helper_process(wait_thr)
        pid = wait_thr.pid
        Process.kill('TERM', pid)
        return if helper_exited_within_grace_period?(wait_thr)
        return unless wait_thr.alive?

        Process.kill('KILL', pid)
        helper_exited_within_grace_period?(wait_thr)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end

      def helper_exited_within_grace_period?(wait_thr)
        !!wait_thr.join(HELPER_TERMINATION_WAIT_SECONDS)
      end

      def ensure_helper_installed
        return if helper_disabled?
        return if @helper_install_verified

        helper_present = File.executable?(helper_executable_path)
        helper_valid = WifiWand::MacOsWifiAuthHelper.helper_installed_and_valid?
        if helper_valid
          @helper_install_verified = true
          return
        end

        if helper_present
          log_verbose('existing helper install failed validation; attempting reinstall')
        else
          log_verbose('helper not installed; running installer')
        end

        WifiWand::MacOsWifiAuthHelper.ensure_helper_installed(out_stream: verbose? ? out_stream : nil)
        @helper_install_verified = true
      rescue => e
        @helper_install_verified = false
        @disabled = true
        emit_install_failure(e.message, repair_required: helper_present)
      end

      def helper_executable_path = WifiWand::MacOsWifiAuthHelper.installed_executable_path

      def helper_disabled?
        @disabled || ENV[DISABLE_ENV_KEY] == '1'
      end

      def parse_json(text)
        JSON.parse(text)
      rescue JSON::ParserError => e
        log_verbose("failed to parse helper JSON: #{e.message}")
        nil
      end

      def handle_error(message)
        return unless message

        @last_error_message = message
        if message.downcase.include?('location services')
          emit_location_warning
        else
          log_verbose("helper error: #{message}")
        end
      end

      def emit_location_warning
        return if @location_warning_emitted

        stream = out_stream || $stdout
        if stream
          stream.puts('wifiwand helper: Location Services denied. ' \
            'Run `wifi-wand-macos-setup` (or `wifi-wand-macos-setup --repair`) ' \
            'to grant location access.')
        end
        @location_warning_emitted = true
      end

      def emit_install_failure(detail, repair_required: false)
        stream = out_stream || $stdout
        if stream
          repair_hint = if repair_required
            ' Run `wifi-wand-macos-setup --repair` to reinstall it.'
          else
            ''
          end
          stream.puts("wifiwand helper: failed to install helper (#{detail}). " \
            "Helper disabled until the next run.#{repair_hint}")
        end
      end

      def log_verbose(message)
        return unless verbose?

        stream = out_stream || $stdout
        stream.puts("wifiwand helper: #{message}") if stream
      end

      def macos_version = @macos_version_proc&.call

      def out_stream = @out_stream_proc&.call

      def verbose? = !!(@verbose_proc && @verbose_proc.call)
    end
  end
end
