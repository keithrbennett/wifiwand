# frozen_string_literal: true

# Manages the lifecycle of the macOS Wi-Fi helper app that runs privileged Swift code.
# The module installs, compiles, and signs the helper bundle per WifiWand version so
# network queries can bypass TCC redactions on Sonoma+ while remaining opt-in via env flag.
# Entry points:
#   * Bundle.ensure_helper_installed -> installs/validates the helper bundle.
#   * Client#connected_network_name -> runs the helper's `current-network` command.
#   * Client#scan_networks -> runs the helper's `scan-networks` command.
#   * Client#available? -> tells callers when the helper can safely be invoked.

require 'open3'
require 'rubygems/version'
require_relative 'artifacts'

module WifiWand
  module Platforms
    module Mac
      module Helper
        module Bundle
          INSTALL_PARENT = File.join(Dir.home, 'Library', 'Application Support', 'WifiWand')
          # Only enable the helper on macOS Sonoma (14.0) and newer where redactions occur
          MINIMUM_HELPER_VERSION = Gem::Version.new('14.0')
          # Allows power users/CI to opt out of helper usage via environment flag
          DISABLE_ENV_KEY = 'WIFIWAND_DISABLE_MAC_HELPER'
          DEFAULT_HELPER_COMMAND_TIMEOUT_SECONDS = 3.0
          SCAN_NETWORKS_HELPER_COMMAND_TIMEOUT_SECONDS = 15.0
          HELPER_TERMINATION_WAIT_SECONDS = 0.25
          HELPER_OUTPUT_READER_JOIN_SECONDS = 0.05
          MANIFEST_FILENAME = 'INSTALL_MANIFEST.json'
          VERSION_DIRECTORY_NOTICE_THRESHOLD = 5

          TimeoutConfiguration = Struct.new(
            :default_helper_command_timeout_seconds,
            :scan_networks_helper_command_timeout_seconds,
            :helper_termination_wait_seconds,
            :helper_output_reader_join_seconds,
            keyword_init: true
          ) do
            def initialize(
              default_helper_command_timeout_seconds: Bundle::DEFAULT_HELPER_COMMAND_TIMEOUT_SECONDS,
              scan_networks_helper_command_timeout_seconds: Bundle::SCAN_NETWORKS_HELPER_COMMAND_TIMEOUT_SECONDS,
              helper_termination_wait_seconds: Bundle::HELPER_TERMINATION_WAIT_SECONDS,
              helper_output_reader_join_seconds: Bundle::HELPER_OUTPUT_READER_JOIN_SECONDS
            )
              super
            end
          end

          HelperSupportStatus = Struct.new(:macos_version, :parsed_version, keyword_init: true) do
            def known? = !!parsed_version

            def supported?
              known? && parsed_version >= MINIMUM_HELPER_VERSION
            end

            def unsupported?
              known? && !supported?
            end

            def unknown? = !known?

            def applicable? = !unsupported?
          end

          module_function def versioned_install_dir = File.join(INSTALL_PARENT, helper_version)

          module_function def installed_bundle_path = File.join(versioned_install_dir, BUNDLE_NAME)

          module_function def installed_executable_path
            File.join(installed_bundle_path, 'Contents', 'MacOS', EXECUTABLE_NAME)
          end

          module_function def helper_install_dir_count
            return 0 unless Dir.exist?(INSTALL_PARENT)

            Dir.children(INSTALL_PARENT)
              .select { |entry| File.directory?(File.join(INSTALL_PARENT, entry)) }
              .select { |entry| helper_install_dir_entry?(entry) }
              .count
          end

          module_function def helper_install_dir_entry?(entry)
            entry_name = entry.to_s
            return false if entry_name.empty? || entry_name.start_with?('.')

            Gem::Version.new(entry_name)
            true
          rescue ArgumentError
            false
          end

          module_function def helper_info
            {
              version:              helper_version,
              installed_bundle:     installed_bundle_path,
              installed_executable: installed_executable_path,
              source_bundle:        source_bundle_path,
            }
          end

          module_function def default_timeout_configuration = TimeoutConfiguration.new

          module_function def helper_command_timeout_seconds(command,
            timeout_configuration: default_timeout_configuration)
            if command == 'scan-networks'
              timeout_configuration.scan_networks_helper_command_timeout_seconds
            else
              timeout_configuration.default_helper_command_timeout_seconds
            end
          end

          module_function def sanitize_macos_version(version)
            return nil unless version

            version_string = version.to_s.strip
            match = version_string.match(/\d+(?:\.\d+)*/)
            match&.[](0)
          end

          module_function def parse_macos_version(version)
            sanitized_version = sanitize_macos_version(version)
            return nil unless sanitized_version

            Gem::Version.new(sanitized_version)
          rescue ArgumentError
            nil
          end

          module_function def helper_support_status_for_macos_version(version)
            HelperSupportStatus.new(
              macos_version:  version,
              parsed_version: parse_macos_version(version)
            )
          end

          module_function def helper_supported_on_macos_version?(version)
            helper_support_status_for_macos_version(version).supported?
          end

          module_function def detect_macos_version
            stdout, _stderr, status = Open3.capture3('sw_vers', '-productVersion')
            return nil unless status.success?

            normalize_detected_macos_version(stdout)
          rescue Errno::ENOENT
            nil
          end

          module_function def normalize_detected_macos_version(version)
            normalized_version = version.to_s.strip
            normalized_version.empty? ? nil : normalized_version
          end

          require_relative 'installer'
          require_relative 'client'

          module_function def helper_installed_and_valid?(timeout_seconds: nil,
            timeout_configuration: default_timeout_configuration)
            Installer.helper_installed_and_valid?(
              timeout_configuration: timeout_configuration,
              **timeout_options(timeout_seconds)
            )
          end

          module_function def ensure_helper_installed(out_stream: $stdout, timeout_seconds: nil,
            timeout_configuration: default_timeout_configuration)
            Installer.ensure_helper_installed(
              out_stream:            out_stream,
              timeout_configuration: timeout_configuration,
              **timeout_options(timeout_seconds)
            )
          end

          module_function def install_helper_bundle(out_stream: $stdout, force: false,
            timeout_configuration: default_timeout_configuration)
            Installer.install_helper_bundle(
              out_stream:            out_stream,
              force:                 force,
              timeout_configuration: timeout_configuration
            )
          end

          module_function def install_lock_path = Installer.install_lock_path

          module_function def install_manifest_path = Installer.install_manifest_path

          module_function def helper_bundle_valid?(bundle_path, timeout_seconds: nil,
            timeout_configuration: default_timeout_configuration)
            Installer.helper_bundle_valid?(
              bundle_path,
              timeout_configuration: timeout_configuration,
              **timeout_options(timeout_seconds)
            )
          end

          module_function def timeout_options(timeout_seconds)
            timeout_seconds ? { timeout_seconds: timeout_seconds } : {}
          end

          module_function def helper_help_output?(command_output)
            Installer.helper_help_output?(command_output)
          end

          module_function def installed_bundle_current? = Installer.installed_bundle_current?

          module_function def run_bounded_helper_command(
            executable_path, command, timeout_seconds: nil, on_timeout: nil,
            timeout_configuration: default_timeout_configuration
          )
            Installer.run_bounded_helper_command(
              executable_path,
              command,
              timeout_seconds:       timeout_seconds,
              on_timeout:            on_timeout,
              timeout_configuration: timeout_configuration
            )
          end

          module_function def terminate_helper_process(wait_thr,
            timeout_configuration: default_timeout_configuration)
            Installer.terminate_helper_process(wait_thr, timeout_configuration: timeout_configuration)
          end

          module_function def helper_exited_within_grace_period?(wait_thr,
            timeout_configuration: default_timeout_configuration)
            Installer.helper_exited_within_grace_period?(wait_thr,
              timeout_configuration: timeout_configuration)
          end

          module_function def with_install_lock(&) = Installer.with_install_lock(&)

          module_function def stage_helper_bundle(staged_bundle_path)
            Installer.stage_helper_bundle(staged_bundle_path)
          end

          module_function def publish_staged_bundle(staged_bundle_path)
            Installer.publish_staged_bundle(staged_bundle_path)
          end

          module_function def publish_release_symlink(release_bundle_path, publish_token)
            Installer.publish_release_symlink(release_bundle_path, publish_token)
          end

          module_function def migrate_legacy_bundle_to_release(release_bundle_path, publish_token)
            Installer.migrate_legacy_bundle_to_release(release_bundle_path, publish_token)
          end

          module_function def bundle_release_path(publish_token)
            Installer.bundle_release_path(publish_token)
          end

          module_function def staged_bundle_symlink_path(publish_token)
            Installer.staged_bundle_symlink_path(publish_token)
          end

          module_function def legacy_executable_symlink_path(publish_token)
            Installer.legacy_executable_symlink_path(publish_token)
          end

          module_function def legacy_info_plist_path = Installer.legacy_info_plist_path

          module_function def legacy_code_resources_path = Installer.legacy_code_resources_path

          module_function def resolved_installed_bundle_target
            Installer.resolved_installed_bundle_target
          end

          module_function def cleanup_previous_release(previous_release_path)
            Installer.cleanup_previous_release(previous_release_path)
          end

          module_function def sync_legacy_bundle_metadata(release_bundle_path, publish_token)
            Installer.sync_legacy_bundle_metadata(release_bundle_path, publish_token)
          end

          module_function def backup_legacy_bundle_metadata(publish_token)
            Installer.backup_legacy_bundle_metadata(publish_token)
          end

          module_function def backup_legacy_metadata_file(path, publish_token)
            Installer.backup_legacy_metadata_file(path, publish_token)
          end

          module_function def restore_legacy_bundle_metadata(backup_paths, publish_token)
            Installer.restore_legacy_bundle_metadata(backup_paths, publish_token)
          end

          module_function def restore_legacy_metadata_file(backup_path, target_path, publish_token)
            Installer.restore_legacy_metadata_file(backup_path, target_path, publish_token)
          end

          module_function def cleanup_legacy_bundle_metadata_backups(backup_paths)
            Installer.cleanup_legacy_bundle_metadata_backups(backup_paths)
          end

          module_function def switch_legacy_bundle_executable(release_bundle_path, publish_token)
            Installer.switch_legacy_bundle_executable(release_bundle_path, publish_token)
          end

          module_function def resolved_legacy_release_target = Installer.resolved_legacy_release_target

          module_function def unique_publish_token = Installer.unique_publish_token

          module_function def write_manifest = Installer.write_manifest

          module_function def read_install_manifest = Installer.read_install_manifest
        end
      end
    end
  end
end
