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
require_relative 'mac_os_helper_artifacts'

module WifiWand
  module MacOsWifiAuthHelper
    INSTALL_PARENT = File.join(Dir.home, 'Library', 'Application Support', 'WifiWand')
    # Only enable the helper on macOS Sonoma (14.0) and newer where redactions occur
    MINIMUM_HELPER_VERSION = Gem::Version.new('14.0')
    # Allows power users/CI to opt out of helper usage via environment flag
    DISABLE_ENV_KEY = 'WIFIWAND_DISABLE_MAC_HELPER'
    HELPER_COMMAND_TIMEOUT_SECONDS =
      (ENV['WIFIWAND_HELPER_TIMEOUT_SECONDS'] || 3.0).to_f
    HELPER_TERMINATION_WAIT_SECONDS = 0.25
    MANIFEST_FILENAME = 'INSTALL_MANIFEST.json'

    # Returns the versioned installation directory in user's Library folder
    #
    # @return [String] absolute path to version-specific installation directory
    #   Example: ~/Library/Application Support/WifiWand/1.2.3
    module_function def versioned_install_dir = File.join(INSTALL_PARENT, helper_version)

    # Returns the path to the installed app bundle in user's Library folder
    #
    # @return [String] absolute path to the installed .app bundle
    #   Example: ~/Library/Application Support/WifiWand/1.2.3/wifiwand-helper.app
    module_function def installed_bundle_path = File.join(versioned_install_dir, BUNDLE_NAME)

    # Returns the path to the compiled executable inside the installed bundle
    #
    # @return [String] absolute path to the executable binary
    #   Example: ~/Library/Application Support/WifiWand/1.2.3/wifiwand-helper.app/Contents/MacOS/wifiwand-helper
    module_function def installed_executable_path = File.join(installed_bundle_path, 'Contents', 'MacOS',
      EXECUTABLE_NAME)

    # Returns a hash containing all helper paths and version information
    #
    # @return [Hash] helper configuration with keys:
    #   - :version - helper version string
    #   - :installed_bundle - path to installed .app bundle
    #   - :installed_executable - path to compiled executable
    #   - :source_bundle - path to bundle template in gem
    module_function def helper_info
      {
        version:              helper_version,
        installed_bundle:     installed_bundle_path,
        installed_executable: installed_executable_path,
        source_bundle:        source_bundle_path,
      }
    end

    # Installation and Compilation Methods
    # =====================================

    # Verifies the helper installation is valid and not corrupted
    #
    # @return [Boolean] true if helper is properly installed and executable
    module_function def helper_installed_and_valid?
      helper_bundle_valid?(installed_bundle_path) && installed_bundle_current?
    end

    # Copies the pre-signed helper bundle into ~/Library and immediately re-validates it.
    # Concurrent installs may briefly leave the bundle incomplete, so we trust the follow-up
    # validation (and let callers retry) instead of attempting multiple installs here.
    module_function def ensure_helper_installed(out_stream: $stdout)
      return installed_bundle_path if helper_installed_and_valid?

      install_helper_bundle(out_stream: out_stream)

      unless helper_installed_and_valid?
        raise 'Helper installation failed validation after installation.'
      end

      installed_bundle_path
    end

    module_function def install_helper_bundle(out_stream: $stdout)
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

    module_function def install_lock_path = File.join(versioned_install_dir, '.install.lock')

    module_function def install_manifest_path = File.join(versioned_install_dir, MANIFEST_FILENAME)

    module_function def helper_bundle_valid?(bundle_path)
      executable_path = File.join(bundle_path, 'Contents', 'MacOS', EXECUTABLE_NAME)
      return false unless File.executable?(executable_path)
      return false unless File.exist?(File.join(bundle_path, 'Contents', 'Info.plist'))

      helper_result = run_bounded_helper_command(executable_path, 'help')
      return false unless helper_result

      # A successful help probe is the contract; different helper builds may write
      # usage text to stdout or stderr, so treat either stream as acceptable output.
      return false unless helper_result[:status].success?

      command_output = "#{helper_result[:stdout]}#{helper_result[:stderr]}".strip
      helper_help_output?(command_output)
    end

    module_function def helper_help_output?(command_output)
      return false if command_output.empty?

      command_output.match?(/wifiwand helper|usage:/i)
    end

    module_function def installed_bundle_current?
      manifest = read_install_manifest

      if manifest
        manifest['helper_version'] == helper_version &&
          manifest['bundle_fingerprint'] == bundle_fingerprint(installed_bundle_path) &&
          manifest['bundle_fingerprint'] == bundle_fingerprint(source_bundle_path)
      else
        false
      end
    end

    module_function def run_bounded_helper_command(executable_path, command, on_timeout: nil)
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

    module_function def terminate_helper_process(wait_thr)
      pid = wait_thr.pid
      Process.kill('TERM', pid)
      return if helper_exited_within_grace_period?(wait_thr)
      return unless wait_thr.alive?

      Process.kill('KILL', pid)
      helper_exited_within_grace_period?(wait_thr)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    module_function def helper_exited_within_grace_period?(wait_thr)
      !!wait_thr.join(HELPER_TERMINATION_WAIT_SECONDS)
    end

    module_function def with_install_lock
      FileUtils.mkdir_p(versioned_install_dir)

      File.open(install_lock_path, File::RDWR | File::CREAT, 0o644) do |lock_file|
        lock_file.flock(File::LOCK_EX)
        yield
      ensure
        lock_file.flock(File::LOCK_UN)
      end
    end

    module_function def stage_helper_bundle(staged_bundle_path)
      FileUtils.cp_r(source_bundle_path, staged_bundle_path)
    end

    module_function def publish_staged_bundle(staged_bundle_path)
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

    module_function def publish_release_symlink(release_bundle_path, publish_token)
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

    module_function def migrate_legacy_bundle_to_release(release_bundle_path, publish_token)
      backup_paths = backup_legacy_bundle_metadata(publish_token)
      sync_legacy_bundle_metadata(release_bundle_path, publish_token)
      switch_legacy_bundle_executable(release_bundle_path, publish_token)
    rescue
      restore_legacy_bundle_metadata(backup_paths, publish_token)
      raise
    ensure
      cleanup_legacy_bundle_metadata_backups(backup_paths) if defined?(backup_paths)
    end

    module_function def bundle_release_path(publish_token) =
      File.join(versioned_install_dir, ".#{BUNDLE_NAME}.release-#{publish_token}")

    module_function def staged_bundle_symlink_path(publish_token)
      "#{installed_bundle_path}.link-#{publish_token}"
    end

    module_function def legacy_executable_symlink_path(publish_token)
      "#{installed_executable_path}.link-#{publish_token}"
    end

    module_function def legacy_info_plist_path = File.join(installed_bundle_path, 'Contents', 'Info.plist')

    module_function def legacy_code_resources_path =
      File.join(installed_bundle_path, 'Contents', '_CodeSignature', 'CodeResources')

    module_function def resolved_installed_bundle_target
      return unless File.symlink?(installed_bundle_path)

      File.expand_path(File.readlink(installed_bundle_path), versioned_install_dir)
    end

    module_function def cleanup_previous_release(previous_release_path)
      return unless previous_release_path
      return unless previous_release_path.start_with?("#{versioned_install_dir}/.#{BUNDLE_NAME}.release-")
      return if previous_release_path == resolved_installed_bundle_target

      FileUtils.rm_rf(previous_release_path)
    end

    module_function def sync_legacy_bundle_metadata(release_bundle_path, publish_token)
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

    module_function def backup_legacy_bundle_metadata(publish_token)
      {
        info_plist:     backup_legacy_metadata_file(legacy_info_plist_path, publish_token),
        code_resources: backup_legacy_metadata_file(legacy_code_resources_path, publish_token),
      }
    end

    module_function def backup_legacy_metadata_file(path, publish_token)
      return unless File.exist?(path)

      backup_path = "#{path}.backup-#{publish_token}"
      FileUtils.cp(path, backup_path)
      backup_path
    end

    module_function def restore_legacy_bundle_metadata(backup_paths, publish_token)
      restore_legacy_metadata_file(backup_paths[:info_plist], legacy_info_plist_path, publish_token)
      restore_legacy_metadata_file(backup_paths[:code_resources], legacy_code_resources_path, publish_token)
    end

    module_function def restore_legacy_metadata_file(backup_path, target_path, publish_token)
      return unless backup_path && File.exist?(backup_path)

      staged_restore_path = "#{target_path}.restore-#{publish_token}"
      FileUtils.cp(backup_path, staged_restore_path)
      File.rename(staged_restore_path, target_path)
    ensure
      FileUtils.rm_f(staged_restore_path) if defined?(staged_restore_path)
    end

    module_function def cleanup_legacy_bundle_metadata_backups(backup_paths)
      FileUtils.rm_f(backup_paths.values.compact)
    end

    module_function def switch_legacy_bundle_executable(release_bundle_path, publish_token)
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

    module_function def resolved_legacy_release_target
      return unless File.symlink?(installed_executable_path)

      File.expand_path(File.readlink(installed_executable_path), versioned_install_dir)
        .sub(%r{/Contents/MacOS/[^/]+\z}, '')
    end

    module_function def unique_publish_token
      "#{Process.pid}-#{Thread.current.object_id}-#{SecureRandom.hex(6)}"
    end

    module_function def write_manifest
      FileUtils.mkdir_p(versioned_install_dir)
      File.write(File.join(versioned_install_dir, 'VERSION'), helper_version)
      File.write(install_manifest_path, JSON.pretty_generate(
        {
          'helper_version'     => helper_version,
          'bundle_fingerprint' => bundle_fingerprint(source_bundle_path),
        }
      ))
    end

    module_function def read_install_manifest
      if File.exist?(install_manifest_path)
        JSON.parse(File.read(install_manifest_path))
      end
    rescue JSON::ParserError
      nil
    end
  end
end

require_relative 'client'
